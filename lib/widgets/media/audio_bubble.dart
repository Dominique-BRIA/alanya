import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle audio — message vocal avec lecture/pause et durée.
class AudioBubble extends StatelessWidget {
  const AudioBubble({
    super.key,
    required this.url,
    this.duration,
    required this.isMe,
    this.onTap,
  });

  final String url;
  final int? duration;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? AlanyaColors.terracotta.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe
                ? AlanyaColors.terracotta.withValues(alpha: 0.2)
                : AlanyaColors.grey200,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Bouton play
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AlanyaColors.terracotta,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            // Barre de progression (visuelle seulement)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Waveform stylisé
                  Row(
                    children: List.generate(20, (i) {
                      final h = (i % 3 == 0) ? 16.0 : (i % 2 == 0) ? 10.0 : 6.0;
                      return Container(
                        width: 3,
                        height: h,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: AlanyaColors.terracotta.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  // Durée
                  Text(
                    MediaHelper.formatDuration(duration),
                    style: TextStyle(
                      fontSize: 11,
                      color: AlanyaColors.grey500,
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
