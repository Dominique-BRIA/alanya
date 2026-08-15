import 'package:flutter/material.dart';
import '../../theme/alanya_theme.dart';
import 'cached_media.dart';

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
    this.caption,
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
  final String? caption;
  final double width;
  final double maxHeight;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final hasCaption = caption != null && caption!.trim().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image (partie haute)
            ClipRRect(
              borderRadius: hasCaption
                  ? const BorderRadius.vertical(top: Radius.circular(11))
                  : BorderRadius.circular(11),
              child: Stack(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: width,
                      maxHeight: hasCaption ? 240 : maxHeight,
                    ),
                    child: CachedMedia(
                      url: imageUrl,
                      token: token,
                      width: width,
                      fit: BoxFit.cover,
                      errorWidget: Container(
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

                  // Timestamp overlay si pas de légende
                  if (!hasCaption && timestamp != null)
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

            // Légende texte en bas sous l'image
            if (hasCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      caption!,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: isMe ? Colors.white : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    if (timestamp != null)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timestamp!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isMe ? Colors.white70 : AlanyaColors.grey600,
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
          ],
        ),
      ),
    );
  }
}
