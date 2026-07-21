import 'package:flutter/material.dart';
import '../../theme/alanya_theme.dart';

/// Bulle d'image dans le chat — style WhatsApp.
/// Affiche l'image en preview cliquable, avec bordures arrondies.
class ImageBubble extends StatelessWidget {
  const ImageBubble({
    super.key,
    required this.url,
    required this.isMe,
    this.maxWidth = 260,
    this.maxHeight = 300,
    this.onTap,
  });

  final String url;
  final bool isMe;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return Container(
                width: maxWidth,
                height: 180,
                color: isMe
                    ? AlanyaColors.terracotta.withValues(alpha: 0.1)
                    : AlanyaColors.grey200,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AlanyaColors.terracotta,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (ctx, err, stack) => Container(
              width: maxWidth,
              height: 120,
              color: AlanyaColors.grey200,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: AlanyaColors.grey400, size: 32),
                  const SizedBox(height: 4),
                  Text('Image indisponible',
                      style: TextStyle(fontSize: 12, color: AlanyaColors.grey400)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
