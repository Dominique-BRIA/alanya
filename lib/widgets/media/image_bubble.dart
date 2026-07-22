import 'package:flutter/material.dart';
import '../../theme/alanya_theme.dart';

/// Bulle image style WhatsApp :
/// - Image plein bulle (pas de bouton download visible)
/// - Timestamp + coches en bas à droite (fond semi-transparent)
/// - Coins arrondis
/// - Pas de loading spinner visible (juste un fond coloré)
class ImageBubble extends StatelessWidget {
  const ImageBubble({
    super.key,
    required this.imageUrl,
    required this.token,
    this.width = 274,
    this.maxHeight = 320,
    this.onTap,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final String imageUrl;
  final String? token;
  final double width;
  final double maxHeight;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final url = token != null ? '$imageUrl?token=$token' : imageUrl;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            // Image plein bulle
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width,
                maxHeight: maxHeight,
              ),
              child: Image.network(
                url,
                width: width,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: width,
                    height: 200,
                    color: AlanyaColors.sand,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AlanyaColors.terracotta,
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  width: width,
                  height: 160,
                  color: AlanyaColors.sand,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: AlanyaColors.grey400, size: 36),
                      const SizedBox(height: 4),
                      Text('Image indisponible',
                          style: TextStyle(fontSize: 12, color: AlanyaColors.grey500)),
                    ],
                  ),
                ),
              ),
            ),

            // Timestamp + coches en bas à droite (style WhatsApp)
            if (timestamp != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timestamp!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (statusWidget != null) ...[
                        const SizedBox(width: 3),
                        statusWidget!,
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
