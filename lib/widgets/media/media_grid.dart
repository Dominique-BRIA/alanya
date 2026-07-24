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
    this.onMoreTap,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final List<MediaGridItem> items;
  final String baseUrl;
  final String? token;
  final void Function(int index)? onItemTap;
  final VoidCallback? onMoreTap; // appelé quand on clique sur "+N"
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  // Cache des thumbnails vidéo générées
  final Map<String, Uint8List> _thumbCache = {};

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    if (widget.items.length == 1) return _buildSingle(context, 0);

    final cols = widget.items.length == 2 ? 2 : (widget.items.length <= 4 ? 2 : 3);
    final displayCount = widget.items.length > 6 ? 6 : widget.items.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 274,
        child: Column(
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: displayCount,
              itemBuilder: (ctx, i) {
                if (i == 5 && widget.items.length > 6) {
                  return _buildMoreOverlay(widget.items.length - 5);
                }
                return _buildGridItem(ctx, i);
              },
            ),
            // Timestamp en bas
            if (widget.timestamp != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
                color: Colors.transparent,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(widget.timestamp!,
                        style: TextStyle(fontSize: 11, color: widget.isMe ? Colors.white70 : Colors.black45)),
                    if (widget.statusWidget != null) ...[
                      const SizedBox(width: 3),
                      widget.statusWidget!,
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingle(BuildContext context, int index) {
    final item = widget.items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);
    final url = '${widget.baseUrl}${item.url}?token=${widget.token}';

    if (type == AlanyaMediaType.image) {
      return GestureDetector(
        onTap: () => widget.onItemTap?.call(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(children: [
            CachedMedia(url: url, width: 274, fit: BoxFit.cover,
                errorWidget: _placeholder(type)),
            if (widget.timestamp != null)
              Positioned(right: 6, bottom: 6, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.timestamp!, style: const TextStyle(fontSize: 11, color: Colors.white)),
                  if (widget.statusWidget != null) ...[const SizedBox(width: 3), widget.statusWidget!],
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

  Widget _buildGridItem(BuildContext context, int index) {
    final item = widget.items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);
    final url = '${widget.baseUrl}${item.url}?token=${widget.token}';
    final thumbKey = item.url;

    return GestureDetector(
      onTap: () => widget.onItemTap?.call(index),
      child: Stack(fit: StackFit.expand, children: [
        // Image ou thumbnail vidéo
        if (type == AlanyaMediaType.image)
          CachedMedia(url: url, fit: BoxFit.cover,
              errorWidget: _placeholder(type))
        else if (type == AlanyaMediaType.video)
          _buildVideoThumbnail(thumbKey, url)
        else
          _placeholder(type),

        // Play icon pour vidéos
        if (type == AlanyaMediaType.video)
          const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 28)),

        // Badge extension pour documents
        if (type != AlanyaMediaType.image && type != AlanyaMediaType.video)
          Positioned(
            bottom: 4, left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Text(
                MediaHelper.extension(item.fileName).toUpperCase().replaceAll('.', ''),
                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
              ),
            ),
          ),

        // Badge durée pour vidéos
        if (type == AlanyaMediaType.video && item.durationMs != null && item.durationMs! > 0)
          Positioned(
            bottom: 4, right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Text(
                MediaHelper.formatDuration(item.durationMs),
                style: const TextStyle(color: Colors.white, fontSize: 8),
              ),
            ),
          ),
      ]),
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
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
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

  Widget _buildMoreOverlay(int remaining) {
    return GestureDetector(
      onTap: widget.onMoreTap, // ← FIX: ouvre la galerie
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('+$remaining',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Icon(Icons.grid_view, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(AlanyaMediaType type) {
    return Container(
      color: widget.isMe ? AlanyaColors.terracotta.withValues(alpha: 0.15) : AlanyaColors.grey200,
      child: Center(child: Icon(MediaHelper.iconForType(type), color: AlanyaColors.grey400, size: 28)),
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
