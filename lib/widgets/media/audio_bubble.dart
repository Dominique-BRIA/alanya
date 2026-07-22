import 'package:flutter/material.dart';
import '../../theme/alanya_theme.dart';

/// Bulle audio/voice style WhatsApp :
/// - Bouton play/pause (cercle coloré)
/// - Waveform dynamique (barres qui bougent avec la lecture)
/// - Progression en temps réel
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
  final double progress; // 0.0 à 1.0
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  // Pattern de hauteurs style WhatsApp (28 barres)
  static const _heights = [
    6.0, 10.0, 14.0, 8.0, 16.0, 12.0, 6.0, 18.0,
    10.0, 14.0, 8.0, 16.0, 12.0, 6.0, 10.0, 14.0,
    8.0, 16.0, 12.0, 6.0, 18.0, 10.0, 14.0, 8.0,
    16.0, 12.0, 6.0, 10.0,
  ];

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
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                  color: accent, size: 20,
                ),
              ),
              const SizedBox(width: 8),
              // Waveform dynamique + durée
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 20,
                      child: Row(
                        children: List.generate(28, (i) {
                          final h = _heights[i % _heights.length];
                          final played = i / 28 < progress;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            width: 3, height: h,
                            margin: const EdgeInsets.only(right: 1.5),
                            decoration: BoxDecoration(
                              color: played ? accent : accent.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(secs != null ? '${secs}s' : '', style: TextStyle(fontSize: 11, color: onSub)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.mic, size: 16, color: onSub),
            ],
          ),
          if (timestamp != null) ...[
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Spacer(),
              Text(timestamp!, style: TextStyle(fontSize: 11, color: onSub)),
              if (statusWidget != null) ...[
                const SizedBox(width: 3),
                statusWidget!,
              ],
            ]),
          ],
        ],
      ),
    );
  }
}
