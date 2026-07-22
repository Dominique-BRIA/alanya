import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Grille de médias multiples dans un seul message — style WhatsApp.
/// 2 images = 2 colonnes, 3+ = grille, max 6 avec "+N" overlay.
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.baseUrl,
    this.token,
    this.onItemTap,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final List<MediaGridItem> items;
  final String baseUrl;
  final String? token;
  final void Function(int index)? onItemTap;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) return _buildSingle(context, 0);

    final cols = items.length == 2 ? 2 : (items.length <= 4 ? 2 : 3);
    final displayCount = items.length > 6 ? 6 : items.length;

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
                if (i == 5 && items.length > 6) return _buildMoreOverlay(items.length - 5);
                return _buildGridItem(ctx, i);
              },
            ),
            // Timestamp en bas
            if (timestamp != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
                color: Colors.transparent,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(timestamp!, style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : Colors.black45)),
                    if (statusWidget != null) ...[
                      const SizedBox(width: 3),
                      statusWidget!,
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
    final item = items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);
    final url = '$baseUrl${item.url}?token=$token';

    if (type == AlanyaMediaType.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(children: [
          Image.network(url, width: 274, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(type)),
          if (timestamp != null)
            Positioned(right: 6, bottom: 6, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(timestamp!, style: const TextStyle(fontSize: 11, color: Colors.white)),
                if (statusWidget != null) ...[const SizedBox(width: 3), statusWidget!],
              ]),
            )),
        ]),
      );
    }
    return _placeholder(type);
  }

  Widget _buildGridItem(BuildContext context, int index) {
    final item = items[index];
    final type = MediaHelper.detectType(item.mimeType, item.fileName);
    final url = '$baseUrl${item.url}?token=$token';

    return GestureDetector(
      onTap: () => onItemTap?.call(index),
      child: Stack(fit: StackFit.expand, children: [
        if (type == AlanyaMediaType.image)
          Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(type))
        else
          _placeholder(type),

        if (type == AlanyaMediaType.video)
          const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 28)),

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
      ]),
    );
  }

  Widget _buildMoreOverlay(int remaining) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Text('+$remaining',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _placeholder(AlanyaMediaType type) {
    return Container(
      color: isMe ? AlanyaColors.terracotta.withValues(alpha: 0.15) : AlanyaColors.grey200,
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
