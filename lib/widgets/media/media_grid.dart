import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';
import 'image_bubble.dart';
import 'video_bubble.dart';
import 'document_bubble.dart';

/// Grille de médias multiples dans un seul message (style WhatsApp).
/// Supporte : images, vidéos, documents en mix.
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.isMe,
    this.onItemTap,
  });

  final List<MediaGridItem> items;
  final bool isMe;
  final void Function(int index)? onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) return _buildSingle(context, 0);

    // 2+ éléments → grille
    final cols = items.length == 2 ? 2 : (items.length <= 4 ? 2 : 3);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 280,
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: items.length > 6 ? 6 : items.length,
          itemBuilder: (ctx, i) {
            if (i == 5 && items.length > 6) {
              // "+N" overlay
              return _buildMoreOverlay(items.length - 5);
            }
            return _buildGridItem(ctx, i);
          },
        ),
      ),
    );
  }

  Widget _buildSingle(BuildContext context, int index) {
    final item = items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);

    if (type == AlanyaMediaType.image) {
      return ImageBubble(
        url: item.url,
        isMe: isMe,
        onTap: () => onItemTap?.call(index),
      );
    }
    if (type == AlanyaMediaType.video) {
      return VideoBubble(
        url: item.url,
        thumbnailUrl: item.thumbnailUrl,
        duration: item.durationMs,
        isMe: isMe,
        onTap: () => onItemTap?.call(index),
      );
    }
    return DocumentBubble(
      url: item.url,
      fileName: item.fileName ?? 'Fichier',
      fileSize: item.sizeBytes,
      mimeType: item.mimeType,
      isMe: isMe,
      onTap: () => onItemTap?.call(index),
    );
  }

  Widget _buildGridItem(BuildContext context, int index) {
    final item = items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);

    return GestureDetector(
      onTap: () => onItemTap?.call(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (type == AlanyaMediaType.image)
            Image.network(
              item.url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(type),
            )
          else if (type == AlanyaMediaType.video)
            item.thumbnailUrl != null
                ? Image.network(item.thumbnailUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(type))
                : _placeholder(type)
          else
            _placeholder(type),

          // Play icon pour vidéos
          if (type == AlanyaMediaType.video)
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
            ),

          // Badge type pour documents
          if (type != AlanyaMediaType.image && type != AlanyaMediaType.video)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  MediaHelper.extension(item.fileName).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(AlanyaMediaType type) {
    return Container(
      color: isMe
          ? AlanyaColors.terracotta.withValues(alpha: 0.15)
          : AlanyaColors.grey200,
      child: Center(
        child: Icon(
          MediaHelper.iconForType(type),
          color: AlanyaColors.grey400,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildMoreOverlay(int remaining) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Text(
          '+$remaining',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
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
  final String? thumbnailUrl;

  const MediaGridItem({
    required this.url,
    this.mimeType,
    this.fileName,
    this.sizeBytes,
    this.durationMs,
    this.thumbnailUrl,
  });
}
