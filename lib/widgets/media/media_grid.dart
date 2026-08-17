import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../core/media_cache.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';
import 'cached_media.dart';

/// Grille de médias multiples dans un seul message — style WhatsApp.
/// 2 images = 2 colonnes, 3+ = grille, max 6 avec "+N" overlay cliquable.
class MediaGrid extends StatefulWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.baseUrl,
    this.token,
    this.onItemTap,
    this.onItemLongPress,
    this.onMoreTap,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final List<MediaGridItem> items;
  final String baseUrl;
  final String? token;
  final void Function(int index)? onItemTap;

  /// Appui long sur UNE cellule. Nécessaire depuis le regroupement à la
  /// lecture : les médias d'une grille peuvent appartenir à des messages
  /// différents, et « répondre » ou « supprimer » ne veut rien dire pour la
  /// grille entière.
  final void Function(int index)? onItemLongPress;

  /// Appui sur « +N ». Reçoit l'index du média SOUS la pastille, pour que la
  /// visionneuse s'ouvre là où l'utilisateur a touché — elle s'ouvrait à 0.
  final void Function(int index)? onMoreTap;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  // Cache des thumbnails vidéo générées
  final Map<String, Uint8List> _thumbCache = {};

  /// Écart entre deux cases.
  ///
  /// 🐛 **L'espacement des grilles était mal géré (constaté sur device le
  /// 17/08/2026).** Deux causes, et aucune n'était un simple réglage :
  ///
  /// 1. La grille était figée à **260 points de large**, quel que soit l'écran
  ///    et quelle que soit la place réellement offerte par la bulle. Sur un
  ///    téléphone étroit elle débordait, sur un large elle laissait une bande
  ///    vide à droite — dans les deux cas l'écart apparent entre les médias
  ///    n'avait plus rien à voir avec l'écart demandé.
  /// 2. Un média SEUL était rendu à **274** points, soit 14 de plus que la
  ///    grille : deux messages successifs, l'un avec une photo et l'autre avec
  ///    trois, n'avaient donc pas la même largeur dans le fil.
  ///
  /// La largeur vient désormais des contraintes reçues (`LayoutBuilder`), et
  /// elle est la MÊME pour une case seule et pour une grille. L'écart passe à 2
  /// points, la valeur de WhatsApp : à 3, les traits entre vignettes se voyaient
  /// plus que les vignettes elles-mêmes.
  static const double _ecart = 2.0;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, contraintes) {
        // `maxWidth` peut être infini si la grille est posée dans un contexte
        // non borné : on retombe alors sur la largeur d'une bulle.
        final largeur =
            contraintes.maxWidth.isFinite ? contraintes.maxWidth : 260.0;
        return _grille(context, largeur);
      },
    );
  }

  Widget _grille(BuildContext context, double w) {
    if (widget.items.length == 1) return _buildSingle(context, 0, w);

    // Dispositions façon WhatsApp selon le nombre de médias.
    const gap = _ecart;
    final n = widget.items.length;
    Widget grid;
    if (n == 2) {
      grid = SizedBox(
        width: w,
        height: (w - gap) / 2,
        child: Row(children: [
          Expanded(child: _cell(0)),
          const SizedBox(width: gap),
          Expanded(child: _cell(1)),
        ]),
      );
    } else if (n == 3) {
      grid = SizedBox(
        width: w,
        height: w,
        child: Row(children: [
          Expanded(child: _cell(0)),
          const SizedBox(width: gap),
          Expanded(
            child: Column(children: [
              Expanded(child: _cell(1)),
              const SizedBox(height: gap),
              Expanded(child: _cell(2)),
            ]),
          ),
        ]),
      );
    } else {
      final more = n > 4 ? n - 4 : 0;
      grid = SizedBox(
        width: w,
        height: w,
        child: Column(children: [
          Expanded(
            child: Row(children: [
              Expanded(child: _cell(0)),
              const SizedBox(width: gap),
              Expanded(child: _cell(1)),
            ]),
          ),
          const SizedBox(height: gap),
          Expanded(
            child: Row(children: [
              Expanded(child: _cell(2)),
              const SizedBox(width: gap),
              Expanded(child: more > 0 ? _moreCell(3, more) : _cell(3)),
            ]),
          ),
        ]),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          grid,
          if (widget.timestamp != null)
            Positioned(right: 6, bottom: 6, child: _timeBadge()),
        ],
      ),
    );
  }

  Widget _cell(int index) => GestureDetector(
        onTap: () => widget.onItemTap?.call(index),
        onLongPress: widget.onItemLongPress != null
            ? () => widget.onItemLongPress!(index)
            : null,
        child: _cellStack(index),
      );

  Widget _moreCell(int index, int more) => GestureDetector(
        onTap: () => widget.onMoreTap?.call(index),
        onLongPress: widget.onItemLongPress != null
            ? () => widget.onItemLongPress!(index)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _cellStack(index),
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              alignment: Alignment.center,
              child: Text('+$more',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _timeBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.timestamp!,
              style: const TextStyle(fontSize: 11, color: Colors.white)),
          if (widget.statusWidget != null) ...[
            const SizedBox(width: 3),
            widget.statusWidget!,
          ],
        ]),
      );

  Widget _buildSingle(BuildContext context, int index, double largeur) {
    final item = widget.items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);
    final url = '${widget.baseUrl}${item.url}?token=${widget.token}';

    if (type == AlanyaMediaType.image) {
      return GestureDetector(
        onLongPress: widget.onItemLongPress != null
            ? () => widget.onItemLongPress!(index)
            : null,
        onTap: () => widget.onItemTap?.call(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(children: [
            // Même largeur qu'une grille : deux messages successifs, l'un avec
            // une photo et l'autre avec trois, s'alignent enfin.
            CachedMedia(
                url: url,
                width: largeur,
                fit: BoxFit.cover,
                errorWidget: _placeholder(type)),
            if (widget.timestamp != null)
              Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.timestamp!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white)),
                      if (widget.statusWidget != null) ...[
                        const SizedBox(width: 3),
                        widget.statusWidget!
                      ],
                    ]),
                  )),
          ]),
        ),
      );
    }
    return GestureDetector(
      onTap: () => widget.onItemTap?.call(index),
      child: _placeholder(type),
    );
  }

  Widget _cellStack(int index) {
    final item = widget.items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);
    final url = '${widget.baseUrl}${item.url}?token=${widget.token}';
    final thumbKey = item.url;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Image ou thumbnail vidéo
        if (type == AlanyaMediaType.image)
          CachedMedia(
              url: url, fit: BoxFit.cover, errorWidget: _placeholder(type))
        else if (type == AlanyaMediaType.video)
          _buildVideoThumbnail(thumbKey, url)
        else
          _placeholder(type),

        // Play icon pour vidéos
        if (type == AlanyaMediaType.video)
          const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white70, size: 28)),

        // Badge extension pour documents
        if (type != AlanyaMediaType.image && type != AlanyaMediaType.video)
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4)),
              child: Text(
                MediaHelper.extension(item.fileName)
                    .toUpperCase()
                    .replaceAll('.', ''),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),

        // Badge durée pour vidéos
        if (type == AlanyaMediaType.video &&
            item.durationMs != null &&
            item.durationMs! > 0)
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4)),
              child: Text(
                MediaHelper.formatDuration(item.durationMs),
                style: const TextStyle(color: Colors.white, fontSize: 8),
              ),
            ),
          ),
      ],
    );
  }

  /// Génère et affiche la thumbnail d'une vidéo.
  Widget _buildVideoThumbnail(String thumbKey, String videoUrl) {
    // Cache hit
    if (_thumbCache.containsKey(thumbKey)) {
      return Image.memory(_thumbCache[thumbKey]!, fit: BoxFit.cover);
    }

    // Génère la thumbnail en async
    _generateThumbnail(thumbKey, videoUrl);

    // Placeholder pendant la génération
    return Container(
      color: const Color(0xFF1A1A2E),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
        ),
      ),
    );
  }

  Future<void> _generateThumbnail(String key, String videoUrl) async {
    try {
      final diskKey = 'vthumb_${CachedMedia.cacheKey(videoUrl)}';
      // Disque d'abord : générée une seule fois (plus de re-téléchargement de
      // la vidéo pour régénérer la vignette).
      final cachedPath = await MediaCache.get(diskKey, 'jpg');
      if (cachedPath != null) {
        final bytes = await File(cachedPath).readAsBytes();
        if (mounted) setState(() => _thumbCache[key] = bytes);
        return;
      }
      final thumb = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 60,
      );
      if (mounted && thumb != null) {
        await MediaCache.put(diskKey, 'jpg', thumb);
        setState(() => _thumbCache[key] = thumb);
      }
    } catch (_) {}
  }

  Widget _placeholder(AlanyaMediaType type) {
    return Container(
      color: widget.isMe
          ? AlanyaColors.terracotta.withValues(alpha: 0.15)
          : AlanyaColors.grey200,
      child: Center(
          child: Icon(MediaHelper.iconForType(type),
              color: AlanyaColors.grey400, size: 28)),
    );
  }
}

/// Un élément de la grille média.
class MediaGridItem {
  final String url;
  final String? mimeType;
  final String? fileName;
  final int? sizeBytes;
  final int? durationMs;

  const MediaGridItem({
    required this.url,
    this.mimeType,
    this.fileName,
    this.sizeBytes,
    this.durationMs,
  });
}
