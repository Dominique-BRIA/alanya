import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle audio/voice style WhatsApp :
/// - Bouton play/pause (cercle coloré)
/// - Barre de progression (waveform simplifié)
/// - Durée texte
/// - Icône micro
class AudioBubble extends StatelessWidget {
  const AudioBubble({
    super.key,
    required this.url,
    this.duration,
    this.isPlaying = false,
    this.progress = 0.0,
    this.onTap,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final String url;
  final int? duration;
  final bool isPlaying;
  final double progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final onSub = isMe ? Colors.white70 : Colors.black45;
    final accent = isMe ? Colors.white : AlanyaColors.terracotta;
    final secs = duration != null ? (duration! ~/ 1000) : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bouton play/pause
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              // Waveform + durée
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Waveform simplifié (barres statiques)
                    SizedBox(
                      height: 20,
                      child: Row(
                        children: List.generate(28, (i) {
                          // Pattern de hauteurs style WhatsApp
                          final heights = [
                            6.0, 10.0, 14.0, 8.0, 16.0, 12.0, 6.0, 18.0,
                            10.0, 14.0, 8.0, 16.0, 12.0, 6.0, 10.0, 14.0,
                            8.0, 16.0, 12.0, 6.0, 18.0, 10.0, 14.0, 8.0,
                            16.0, 12.0, 6.0, 10.0,
                          ];
                          final h = heights[i % heights.length];
                          final played = i / 28 < progress;
                          return Container(
                            width: 3,
                            height: h,
                            margin: const EdgeInsets.only(right: 1.5),
                            decoration: BoxDecoration(
                              color: played
                                  ? accent
                                  : accent.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Durée
                    Text(
                      secs != null ? '${secs}s' : '',
                      style: TextStyle(fontSize: 11, color: onSub),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Icône micro
              Icon(Icons.mic, size: 16, color: onSub),
            ],
          ),

          // Timestamp + coches
          if (timestamp != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                Text(
                  timestamp!,
                  style: TextStyle(fontSize: 11, color: onSub),
                ),
                if (statusWidget != null) ...[
                  const SizedBox(width: 3),
                  statusWidget!,
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
