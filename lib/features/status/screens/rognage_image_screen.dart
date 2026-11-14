import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/compression_image.dart' show imageBordMax;
import '../../../l10n/app_localizations.dart';

/// ROGNER ET FAIRE PIVOTER UNE PHOTO DE STATUT (14/11/2026, demande du user :
/// « comme sur WhatsApp »).
///
/// Écrit en Flutter pur, comme l'application de référence
/// (`media_editor/photo_tool_screen.dart`), et non avec `image_cropper` :
/// pas d'activité native à déclarer dans le manifeste, rien de plus à faire
/// passer par la CI.
///
/// Le cadre se décrit en FRACTIONS de l'image pivotée (0 → 1) : il ne dépend
/// ni de la taille de l'écran ni de celle de la photo. Le rendu final redessine
/// l'image d'origine, pivotée puis rognée, à pleine résolution (bornée à
/// [imageBordMax]).
///
/// Rend les octets PNG de l'image obtenue, ou `null` si l'utilisateur annule.
class RognageImageScreen extends StatefulWidget {
  const RognageImageScreen({super.key, required this.octets});

  final Uint8List octets;

  static Future<Uint8List?> ouvrir(BuildContext context, Uint8List octets) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => RognageImageScreen(octets: octets),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<RognageImageScreen> createState() => _RognageImageScreenState();
}

/// Ce que le doigt a saisi au début du geste.
enum _Prise { aucune, deplacer, hautGauche, hautDroite, basGauche, basDroite }

class _RognageImageScreenState extends State<RognageImageScreen> {
  ui.Image? _image;
  bool _echec = false;
  bool _calcul = false;

  /// Quarts de tour dans le sens des aiguilles d'une montre (0 → 3).
  int _quarts = 0;

  /// Le cadre, en fractions de l'image PIVOTÉE.
  Rect _cadre = const Rect.fromLTRB(0, 0, 1, 1);

  /// Format imposé : `null` = libre, sinon largeur / hauteur en pixels.
  double? _format;

  _Prise _prise = _Prise.aucune;

  /// Le plus petit côté permis, en fraction : en dessous, les poignées se
  /// chevauchent et le cadre ne se saisit plus.
  static const _minimum = 0.08;

  @override
  void initState() {
    super.initState();
    _decoder();
  }

  Future<void> _decoder() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.octets);
      final trame = await codec.getNextFrame();
      if (mounted) setState(() => _image = trame.image);
    } catch (_) {
      if (mounted) setState(() => _echec = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Largeur et hauteur de l'image une fois pivotée, en pixels.
  Size get _taillePivotee {
    final i = _image!;
    return _quarts.isOdd
        ? Size(i.height.toDouble(), i.width.toDouble())
        : Size(i.width.toDouble(), i.height.toDouble());
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Un quart de tour vers la GAUCHE, comme WhatsApp. Le cadre repart de
  /// l'image entière : l'ancien n'aurait plus de sens après pivot.
  void _pivoter() {
    setState(() {
      _quarts = (_quarts + 3) % 4;
      _cadre = const Rect.fromLTRB(0, 0, 1, 1);
      if (_format != null) _cadre = _cadreAuFormat(_format!);
    });
  }

  void _choisirFormat(double? format) {
    setState(() {
      _format = format;
      _cadre = format == null ? const Rect.fromLTRB(0, 0, 1, 1) : _cadreAuFormat(format);
    });
  }

  /// Le plus grand cadre centré au format [f] (largeur / hauteur en pixels).
  Rect _cadreAuFormat(double f) {
    final t = _taillePivotee;
    var l = t.width, h = t.width / f;
    if (h > t.height) {
      h = t.height;
      l = h * f;
    }
    final fl = l / t.width, fh = h / t.height;
    return Rect.fromLTWH((1 - fl) / 2, (1 - fh) / 2, fl, fh);
  }

  void _reinitialiser() {
    setState(() {
      _quarts = 0;
      _format = null;
      _cadre = const Rect.fromLTRB(0, 0, 1, 1);
    });
  }

  // ── Gestes ───────────────────────────────────────────────────────────────

  void _debut(Offset local, Rect affichage) {
    final c = _versEcran(_cadre, affichage);
    const rayon = 32.0;
    final coins = {
      _Prise.hautGauche: c.topLeft,
      _Prise.hautDroite: c.topRight,
      _Prise.basGauche: c.bottomLeft,
      _Prise.basDroite: c.bottomRight,
    };
    for (final e in coins.entries) {
      if ((e.value - local).distance <= rayon) {
        _prise = e.key;
        return;
      }
    }
    _prise = c.contains(local) ? _Prise.deplacer : _Prise.aucune;
  }

  void _suite(Offset delta, Rect affichage) {
    if (_prise == _Prise.aucune) return;
    final dx = delta.dx / affichage.width;
    final dy = delta.dy / affichage.height;
    var r = _cadre;

    if (_prise == _Prise.deplacer) {
      final nx = (r.left + dx).clamp(0.0, 1.0 - r.width);
      final ny = (r.top + dy).clamp(0.0, 1.0 - r.height);
      setState(() => _cadre = Rect.fromLTWH(nx, ny, r.width, r.height));
      return;
    }

    var l = r.left, t = r.top, d = r.right, b = r.bottom;
    switch (_prise) {
      case _Prise.hautGauche:
        l += dx;
        t += dy;
      case _Prise.hautDroite:
        d += dx;
        t += dy;
      case _Prise.basGauche:
        l += dx;
        b += dy;
      case _Prise.basDroite:
        d += dx;
        b += dy;
      default:
        break;
    }
    l = l.clamp(0.0, d - _minimum);
    d = d.clamp(l + _minimum, 1.0);
    t = t.clamp(0.0, b - _minimum);
    b = b.clamp(t + _minimum, 1.0);

    // Format imposé : la hauteur suit la largeur, du côté du coin saisi.
    final f = _format;
    if (f != null) {
      final ts = _taillePivotee;
      var hauteur = (d - l) * ts.width / f / ts.height;
      final enHaut = _prise == _Prise.hautGauche || _prise == _Prise.hautDroite;
      if (enHaut) {
        t = b - hauteur;
        if (t < 0) {
          t = 0;
          hauteur = b;
          final largeur = hauteur * ts.height * f / ts.width;
          if (_prise == _Prise.hautGauche) {
            l = d - largeur;
          } else {
            d = l + largeur;
          }
        }
      } else {
        b = t + hauteur;
        if (b > 1) {
          b = 1;
          hauteur = 1 - t;
          final largeur = hauteur * ts.height * f / ts.width;
          if (_prise == _Prise.basGauche) {
            l = d - largeur;
          } else {
            d = l + largeur;
          }
        }
      }
      if (l < 0 || d > 1 || b - t < _minimum) return;
    }
    setState(() => _cadre = Rect.fromLTRB(l, t, d, b));
  }

  Rect _versEcran(Rect fraction, Rect affichage) => Rect.fromLTRB(
        affichage.left + fraction.left * affichage.width,
        affichage.top + fraction.top * affichage.height,
        affichage.left + fraction.right * affichage.width,
        affichage.top + fraction.bottom * affichage.height,
      );

  // ── Rendu final ──────────────────────────────────────────────────────────

  /// Redessine l'original, pivoté puis rogné, et le rend en PNG.
  ///
  /// ⚠️ PNG, PARCE QUE FLUTTER NE SAIT EXPORTER QUE ÇA — même contrainte que
  /// l'aplatissement de l'éditeur (`toByteData`).
  Future<void> _valider() async {
    final image = _image;
    if (image == null || _calcul) return;
    setState(() => _calcul = true);
    try {
      final ts = _taillePivotee;
      final rognage = Rect.fromLTRB(
        _cadre.left * ts.width,
        _cadre.top * ts.height,
        _cadre.right * ts.width,
        _cadre.bottom * ts.height,
      );
      final cote = math.max(rognage.width, rognage.height);
      final echelle = cote > imageBordMax ? imageBordMax / cote : 1.0;
      final largeur = math.max(1, (rognage.width * echelle).round());
      final hauteur = math.max(1, (rognage.height * echelle).round());

      final enregistreur = ui.PictureRecorder();
      final toile = Canvas(enregistreur);
      toile.scale(echelle);
      toile.translate(-rognage.left, -rognage.top);
      final w = image.width.toDouble(), h = image.height.toDouble();
      switch (_quarts) {
        case 1:
          toile.translate(h, 0);
          toile.rotate(math.pi / 2);
        case 2:
          toile.translate(w, h);
          toile.rotate(math.pi);
        case 3:
          toile.translate(0, w);
          toile.rotate(3 * math.pi / 2);
      }
      toile.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.high);
      final resultat = await enregistreur.endRecording().toImage(largeur, hauteur);
      final donnees = await resultat.toByteData(format: ui.ImageByteFormat.png);
      resultat.dispose();
      if (!mounted) return;
      if (donnees == null) {
        setState(() => _calcul = false);
        return;
      }
      Navigator.of(context).pop(donnees.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _calcul = false);
    }
  }

  // ── Écran ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(children: [
              IconButton(
                tooltip: tr(context, 'cancel'),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(tr(context, 'rogner_titre'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _reinitialiser,
                child: Text(tr(context, 'rogner_reinitialiser'),
                    style: const TextStyle(color: Colors.white70)),
              ),
            ]),
            Expanded(child: _zone()),
            _barreBas(),
          ],
        ),
      ),
    );
  }

  Widget _zone() {
    final image = _image;
    if (_echec) {
      return Center(
        child: Text(tr(context, 'rogner_illisible'),
            style: const TextStyle(color: Colors.white70)),
      );
    }
    if (image == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return LayoutBuilder(builder: (_, bc) {
      // L'image pivotée, contenue dans la zone avec une marge pour les poignées.
      const marge = 20.0;
      final dispo = Size(bc.maxWidth - 2 * marge, bc.maxHeight - 2 * marge);
      final ts = _taillePivotee;
      final f = math.min(dispo.width / ts.width, dispo.height / ts.height);
      final taille = Size(ts.width * f, ts.height * f);
      final affichage = Rect.fromLTWH(
        (bc.maxWidth - taille.width) / 2,
        (bc.maxHeight - taille.height) / 2,
        taille.width,
        taille.height,
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _debut(d.localPosition, affichage),
        onPanUpdate: (d) => _suite(d.delta, affichage),
        onPanEnd: (_) => _prise = _Prise.aucune,
        child: Stack(children: [
          Positioned.fromRect(
            rect: affichage,
            child: RotatedBox(
              quarterTurns: _quarts,
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _PeintreCadre(_versEcran(_cadre, affichage)),
            ),
          ),
        ]),
      );
    });
  }

  Widget _barreBas() {
    Widget format(String cle, double? valeur, IconData icone) {
      final actif = _format == valeur;
      return TextButton.icon(
        onPressed: _image == null ? null : () => _choisirFormat(valeur),
        icon: Icon(icone, color: actif ? const Color(0xFF43A047) : Colors.white, size: 20),
        label: Text(tr(context, cle),
            style: TextStyle(color: actif ? const Color(0xFF43A047) : Colors.white)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
      child: Row(children: [
        IconButton(
          tooltip: tr(context, 'rogner_pivoter'),
          icon: const Icon(Icons.rotate_90_degrees_ccw, color: Colors.white),
          onPressed: _image == null ? null : _pivoter,
        ),
        format('rogner_libre', null, Icons.crop_free),
        format('rogner_carre', 1, Icons.crop_square),
        const Spacer(),
        FloatingActionButton(
          backgroundColor: Colors.white,
          tooltip: tr(context, 'validate'),
          onPressed: _image == null || _calcul ? null : _valider,
          child: _calcul
              ? const CircularProgressIndicator()
              : const Icon(Icons.check, color: Colors.black),
        ),
      ]),
    );
  }
}

/// Assombrit l'extérieur du cadre, trace son bord, sa grille des tiers et ses
/// quatre poignées.
class _PeintreCadre extends CustomPainter {
  const _PeintreCadre(this.cadre);

  final Rect cadre;

  @override
  void paint(Canvas canvas, Size size) {
    final dehors = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(cadre);
    canvas.drawPath(dehors, Paint()..color = Colors.black54);

    final trait = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(cadre, trait);

    final grille = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = cadre.left + cadre.width * i / 3;
      final y = cadre.top + cadre.height * i / 3;
      canvas.drawLine(Offset(x, cadre.top), Offset(x, cadre.bottom), grille);
      canvas.drawLine(Offset(cadre.left, y), Offset(cadre.right, y), grille);
    }

    final poignee = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 18.0;
    for (final (coin, sx, sy) in [
      (cadre.topLeft, 1.0, 1.0),
      (cadre.topRight, -1.0, 1.0),
      (cadre.bottomLeft, 1.0, -1.0),
      (cadre.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(coin, coin + Offset(l * sx, 0), poignee);
      canvas.drawLine(coin, coin + Offset(0, l * sy), poignee);
    }
  }

  @override
  bool shouldRepaint(_PeintreCadre ancien) => ancien.cadre != cadre;
}
