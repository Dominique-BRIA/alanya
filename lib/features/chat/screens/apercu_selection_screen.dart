import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

/// APERÇU DE LA SÉLECTION — les photos, et rien d'autre.
///
/// 🔴 CE N'EST PAS L'ÉCRAN D'ENVOI (précision du user, 30/08/2026). Le bouton
/// « Prévisualiser » sert à REGARDER ce qu'on vient de cocher, en grand, avant
/// de valider : pas de légende, pas de bouton d'envoi, pas de suppression. On
/// revient au sélecteur par le retour, la sélection intacte.
///
/// L'écran qui porte la légende et l'envoi est `MediaCaptionScreen`, et c'est
/// « OK » qui y mène.
///
/// ⚠️ Les images passent par `thumbnailDataWithSize` et non `originBytes` :
/// c'est un aperçu, et charger dix photos en pleine définition pour les
/// regarder une seconde coûterait plusieurs dizaines de mégaoctets en mémoire.
/// La vignette demandée est déjà plus grande que l'écran du téléphone.
class ApercuSelectionScreen extends StatefulWidget {
  const ApercuSelectionScreen({
    super.key,
    required this.assets,
    this.depart = 0,
  });

  final List<AssetEntity> assets;

  /// Média affiché en premier.
  final int depart;

  static Future<void> ouvrir(
    BuildContext context,
    List<AssetEntity> assets, {
    int depart = 0,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ApercuSelectionScreen(assets: assets, depart: depart),
      ),
    );
  }

  @override
  State<ApercuSelectionScreen> createState() => _ApercuSelectionScreenState();
}

class _ApercuSelectionScreenState extends State<ApercuSelectionScreen> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.depart.clamp(0, widget.assets.length - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          "${_index + 1} / ${widget.assets.length}",
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: PageView.builder(
          controller: _pages,
          itemCount: widget.assets.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => Center(child: _media(widget.assets[i], i == _index)),
        ),
      ),
    );
  }

  /// [courant] : c'est la page à l'écran — la seule dont la vidéo se lit.
  Widget _media(AssetEntity asset, bool courant) {
    return FutureBuilder(
      // 1080 de large : au-delà, l'écran d'un téléphone n'y gagne rien.
      future: asset.thumbnailDataWithSize(const ThumbnailSize(1080, 1920)),
      builder: (context, instantane) {
        final octets = instantane.data;
        if (octets == null) {
          return const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
          );
        }
        final image = InteractiveViewer(
          maxScale: 4,
          child: Image.memory(octets, fit: BoxFit.contain),
        );
        if (asset.type != AssetType.video) return image;
        /*
         * 🐛 « IMPOSSIBLE DE LIRE UNE VIDÉO EN PRÉVISUALISATION » (user,
         * 12/10/2026). L'aperçu ne montrait que la VIGNETTE, avec un symbole de
         * lecture décoratif : on appuyait, rien ne se passait. Elle se lit
         * désormais — mais seulement sur la page affichée : un lecteur par page
         * ouvrirait autant de décodeurs vidéo que de médias cochés. Les pages
         * voisines gardent la vignette, et le lecteur est libéré dès qu'on
         * tourne la page.
         */
        if (courant) {
          return _LecteurApercu(
              key: ValueKey(asset.id), asset: asset, vignette: image);
        }
        return Stack(alignment: Alignment.center, children: [
          image,
          const IgnorePointer(
            child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
          ),
        ]);
      },
    );
  }
}

/// La vidéo de la page affichée, lisible : appui pour lire ou mettre en pause.
///
/// ⚠️ LA VIGNETTE RESTE TANT QUE LE LECTEUR N'EST PAS PRÊT — et pour de bon
/// s'il échoue (format que le téléphone ne sait pas lire) : mieux vaut une
/// image fixe qu'un écran noir.
class _LecteurApercu extends StatefulWidget {
  const _LecteurApercu({super.key, required this.asset, required this.vignette});

  final AssetEntity asset;
  final Widget vignette;

  @override
  State<_LecteurApercu> createState() => _LecteurApercuState();
}

class _LecteurApercuState extends State<_LecteurApercu> {
  VideoPlayerController? _lecteur;
  bool _echec = false;

  @override
  void initState() {
    super.initState();
    _preparer();
  }

  Future<void> _preparer() async {
    try {
      // Le fichier d'origine, sur l'appareil : `video_player` lit un chemin.
      final File? fichier = await widget.asset.file;
      if (fichier == null || !mounted) {
        if (mounted) setState(() => _echec = true);
        return;
      }
      final c = VideoPlayerController.file(fichier);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _lecteur = c);
      await c.play();
    } catch (_) {
      if (mounted) setState(() => _echec = true);
    }
  }

  @override
  void dispose() {
    _lecteur?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _lecteur;
    if (c == null || !c.value.isInitialized) {
      return Stack(alignment: Alignment.center, children: [
        widget.vignette,
        if (!_echec)
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
      ]);
    }
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        ValueListenableBuilder(
          valueListenable: c,
          builder: (context, valeur, _) => valeur.isPlaying
              ? const SizedBox.shrink()
              : const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VideoProgressIndicator(c, allowScrubbing: true),
        ),
      ]),
    );
  }
}
