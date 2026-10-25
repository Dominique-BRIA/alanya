import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import 'stickers_service.dart';

/// La forme du sticker : ses coins deviennent TRANSPARENTS dans l'image.
enum FormeSticker { arrondi, rond, carre }

/// CRÉER UN STICKER (25/10/2026, demande du user : « comme sur WhatsApp »).
///
/// Une photo (galerie ou appareil), cadrée dans un carré en la déplaçant et
/// en la zoomant, un texte facultatif, une forme ; « Envoyer » la range en
/// tête de « Mes créations » et l'envoie aussitôt — c'est ce que fait
/// WhatsApp. Rend le sticker créé, `null` si l'on renonce.
///
/// Le cadre est CAPTURÉ tel qu'on le voit ([RepaintBoundary]) en PNG de
/// 512 px de côté : ce que le serveur attend (`POST /api/stickers/assets`).
class CreerStickerScreen extends StatefulWidget {
  const CreerStickerScreen({super.key, this.photo});

  /// Une photo déjà choisie (tests) ; sinon l'écran propose de la choisir.
  final Uint8List? photo;

  static Future<Sticker?> ouvrir(BuildContext context) =>
      Navigator.of(context).push<Sticker>(
        MaterialPageRoute(builder: (_) => const CreerStickerScreen()),
      );

  @override
  State<CreerStickerScreen> createState() => _CreerStickerScreenState();
}

/// 512 px : la taille d'un sticker de WhatsApp, et ce que le serveur accepte.
const _cote = 512.0;

class _CreerStickerScreenState extends State<CreerStickerScreen> {
  final _cadre = GlobalKey();
  final _texte = TextEditingController();
  Uint8List? _photo;
  FormeSticker _forme = FormeSticker.arrondi;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _choisir(ImageSource source) async {
    try {
      final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600);
      if (f == null || !mounted) return;
      final octets = await f.readAsBytes();
      if (mounted) setState(() => _photo = octets);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(trLu(context, 'stickers_erreur'))),
        );
      }
    }
  }

  /// Le cadre, tel qu'il est à l'écran, en PNG de 512 px.
  Future<Uint8List> _capturer() async {
    final boite = _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boite.toImage(pixelRatio: _cote / boite.size.width);
    final donnees = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return donnees!.buffer.asUint8List();
  }

  Future<void> _envoyer() async {
    setState(() => _envoi = true);
    final service = context.read<StickersService>();
    final navigateur = Navigator.of(context);
    final messager = ScaffoldMessenger.of(context);
    final erreur = trLu(context, 'stickers_erreur');
    try {
      final sticker = await service.creer(await _capturer());
      navigateur.pop(sticker);
    } catch (_) {
      messager.showSnackBar(SnackBar(content: Text(erreur)));
      if (mounted) setState(() => _envoi = false);
    }
  }

  BorderRadius get _coins => switch (_forme) {
    FormeSticker.arrondi => BorderRadius.circular(48),
    FormeSticker.rond => BorderRadius.circular(1000),
    FormeSticker.carre => BorderRadius.zero,
  };

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'stickers_creer_titre'))),
      body: SafeArea(
        child: photo == null ? _choixPhoto(context) : _editeur(context, photo),
      ),
    );
  }

  Widget _choixPhoto(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_photo_alternate_outlined, size: 64),
          const SizedBox(height: 12),
          Text(tr(context, 'stickers_creer_aide'), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('creer_galerie'),
            onPressed: () => _choisir(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(tr(context, 'stickers_galerie')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _choisir(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(tr(context, 'stickers_camera')),
          ),
        ],
      ),
    ),
  );

  Widget _editeur(BuildContext context, Uint8List photo) {
    final texte = _texte.text.trim();
    const style = TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.1);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 1,
              // Le damier dit « ici, ce sera transparent ».
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RepaintBoundary(
                  key: _cadre,
                  child: ClipRRect(
                    borderRadius: _coins,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: Image.memory(photo, fit: BoxFit.cover),
                        ),
                        if (texte.isNotEmpty)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 14,
                            child: IgnorePointer(
                              child: Stack(
                                children: [
                                  // Le contour noir, puis le texte blanc : lisible
                                  // sur n'importe quelle photo.
                                  Text(
                                    texte,
                                    textAlign: TextAlign.center,
                                    style: style.copyWith(
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = 6
                                        ..color = Colors.black,
                                    ),
                                  ),
                                  Text(
                                    texte,
                                    textAlign: TextAlign.center,
                                    style: style.copyWith(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'stickers_cadre_aide'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('creer_texte'),
          controller: _texte,
          maxLength: 40,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr(context, 'stickers_texte'),
            prefixIcon: const Icon(Icons.text_fields),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final (f, cle) in [
              (FormeSticker.arrondi, 'stickers_forme_arrondi'),
              (FormeSticker.rond, 'stickers_forme_rond'),
              (FormeSticker.carre, 'stickers_forme_carre'),
            ])
              ChoiceChip(
                label: Text(tr(context, cle)),
                selected: _forme == f,
                onSelected: (_) => setState(() => _forme = f),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton.icon(
              onPressed: _envoi ? null : () => setState(() => _photo = null),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(tr(context, 'stickers_autre_photo')),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('creer_envoyer'),
              onPressed: _envoi ? null : _envoyer,
              icon: _envoi
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(tr(context, 'stickers_envoyer')),
            ),
          ],
        ),
      ],
    );
  }
}
