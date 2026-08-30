import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

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
          itemBuilder: (_, i) => Center(child: _media(widget.assets[i])),
        ),
      ),
    );
  }

  Widget _media(AssetEntity asset) {
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
        // Une vidéo garde son symbole de lecture : l'aperçu ne la joue pas — le
        // faire ici demanderait un lecteur par page, alors que l'écran d'envoi
        // le fait déjà. Sans ce symbole, une vidéo passerait pour une photo.
        if (asset.type != AssetType.video) return image;
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
