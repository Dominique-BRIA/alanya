import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// RECADRER LA PHOTO DE PROFIL AVANT DE LA PUBLIER (01/11/2026, demande du
/// user) : un aperçu d'abord, où l'on zoome et déplace la photo sous un
/// cercle — ce que les autres verront.
///
/// ⚠️ SANS DÉPENDANCE : les recadreurs du marché ouvrent une activité native
/// (à déclarer dans le manifeste) ou embarquent un encodeur d'images entier.
/// Ici, `InteractiveViewer` pour le geste, `dart:ui` pour la découpe, et un
/// PNG carré de [cote] pixels en sortie — une photo de profil n'en demande pas
/// davantage, et elle reste loin de la limite d'envoi.
///
/// Rend les octets du PNG recadré, ou `null` si l'on annule.
class RecadragePhotoScreen extends StatefulWidget {
  const RecadragePhotoScreen({super.key, required this.octets, this.cote = 640});

  final Uint8List octets;
  final int cote;

  static Future<Uint8List?> ouvrir(BuildContext context, Uint8List octets) =>
      Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => RecadragePhotoScreen(octets: octets)),
      );

  @override
  State<RecadragePhotoScreen> createState() => _RecadragePhotoScreenState();
}

class _RecadragePhotoScreenState extends State<RecadragePhotoScreen> {
  final _transformation = TransformationController();
  ui.Image? _image;
  bool _echec = false;
  bool _decoupe = false;

  /// Le côté du carré visible, et l'échelle qui y fait tenir le petit côté de
  /// l'image : connus au premier tracé.
  double _fenetre = 0;
  double _echelleBase = 1;

  @override
  void initState() {
    super.initState();
    _decoder();
  }

  Future<void> _decoder() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.octets);
      final trame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _image = trame.image);
    } catch (_) {
      if (mounted) setState(() => _echec = true);
    }
  }

  @override
  void dispose() {
    _transformation.dispose();
    _image?.dispose();
    super.dispose();
  }

  /// Place l'image centrée, son petit côté remplissant le carré.
  void _centrer(ui.Image img, double fenetre) {
    if (_fenetre == fenetre) return;
    _fenetre = fenetre;
    _echelleBase = fenetre / math.min(img.width, img.height);
    final dx = (img.width * _echelleBase - fenetre) / 2;
    final dy = (img.height * _echelleBase - fenetre) / 2;
    // Modifiée SUR PLACE, sans prévenir : on est en pleine mise en page, et
    // `InteractiveViewer` relit la matrice juste après, en se construisant.
    _transformation.value.setFrom(Matrix4.identity()..translate(-dx, -dy));
  }

  /// Découpe ce que montre le carré, et le rend en PNG.
  Future<void> _valider() async {
    final img = _image;
    if (img == null || _decoupe) return;
    setState(() => _decoupe = true);
    try {
      final m = _transformation.value;
      final zoom = m.getMaxScaleOnAxis();
      final t = m.getTranslation();
      // Du carré vers l'image affichée, puis vers les pixels de l'image.
      final echelle = zoom * _echelleBase;
      var cotePixels = _fenetre / echelle;
      var x = -t.x / echelle;
      var y = -t.y / echelle;
      cotePixels = math.min(cotePixels, math.min(img.width, img.height).toDouble());
      x = x.clamp(0.0, img.width - cotePixels);
      y = y.clamp(0.0, img.height - cotePixels);

      final sortie = math.min(widget.cote, cotePixels.round()).clamp(1, widget.cote);
      final enregistreur = ui.PictureRecorder();
      Canvas(enregistreur).drawImageRect(
        img,
        Rect.fromLTWH(x, y, cotePixels, cotePixels),
        Rect.fromLTWH(0, 0, sortie.toDouble(), sortie.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final rendu = await enregistreur.endRecording().toImage(sortie, sortie);
      final png = await rendu.toByteData(format: ui.ImageByteFormat.png);
      rendu.dispose();
      if (!mounted) return;
      Navigator.of(context).pop(png?.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _decoupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr(context, 'crop_title')),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _echec
                ? Center(
                    child: Text(tr(context, 'crop_failed'),
                        style: const TextStyle(color: Colors.white70)),
                  )
                : img == null
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : LayoutBuilder(builder: (context, c) {
                        final fenetre = math.min(c.maxWidth, c.maxHeight) - 32;
                        _centrer(img, fenetre);
                        return Center(
                          child: SizedBox(
                            width: fenetre,
                            height: fenetre,
                            child: Stack(children: [
                              // ⚠️ `constrained: false` ET AUCUNE MARGE : l'image
                              // couvre toujours le carré, on ne peut pas la tirer
                              // au point de laisser du vide dans la photo.
                              InteractiveViewer(
                                transformationController: _transformation,
                                constrained: false,
                                boundaryMargin: EdgeInsets.zero,
                                minScale: 1,
                                maxScale: 6,
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox(
                                  width: img.width * _echelleBase,
                                  height: img.height * _echelleBase,
                                  child: RawImage(image: img, fit: BoxFit.fill),
                                ),
                              ),
                              // Le cercle : ce que les autres verront.
                              IgnorePointer(
                                child: CustomPaint(
                                  size: Size.square(fenetre),
                                  painter: _MasqueRond(),
                                ),
                              ),
                            ]),
                          ),
                        );
                      }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(tr(context, 'crop_hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  onPressed: _decoupe ? null : () => Navigator.of(context).pop(),
                  child: Text(tr(context, 'cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: img == null || _decoupe ? null : _valider,
                  child: _decoupe
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(tr(context, 'crop_validate')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Assombrit ce qui sort du cercle, et trace son bord.
class _MasqueRond extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cercle = Rect.fromLTWH(0, 0, size.width, size.height);
    final voile = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(cercle)
      ..addOval(cercle);
    canvas.drawPath(voile, Paint()..color = Colors.black54);
    canvas.drawOval(
      cercle.deflate(1),
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
