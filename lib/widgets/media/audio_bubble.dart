import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/audio_player.dart';
import '../../theme/alanya_theme.dart';

/// Bulle audio/voice style WhatsApp — CONNECTÉE au lecteur audio.
/// Écoute InlineAudioPlayer.state en temps réel via ValueListenableBuilder.
class AudioBubble extends StatelessWidget {
  const AudioBubble({
    super.key,
    required this.url,
    this.duration,
    this.onTap,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final String url;
  final int? duration;
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
    // Nuit : dans une bulle reçue, l'onde et le bouton de lecture passent en
    // terre cuite claire (le modèle en fait le seul accent chaud de la bulle).
    // Le mode clair est inchangé.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onSub =
        isMe ? Colors.white70 : (dark ? AlanyaColors.craie2 : Colors.black45);
    final accent = isMe
        ? Colors.white
        : (dark ? AlanyaColors.terracottaNuitLight : AlanyaColors.terracotta);
    final totalDuration = duration != null ? Duration(milliseconds: duration!) : null;
    final secs = duration != null ? (duration! ~/ 1000) : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Écoute le lecteur audio en temps réel
          ValueListenableBuilder<AudioPlaybackState>(
            valueListenable: InlineAudioPlayer.state,
            builder: (context, audioState, _) {
              final isActive = audioState.url == url;
              final isPlaying = isActive && audioState.isPlaying;

              // Calcul progression
              double progress = 0;
              if (isActive) {
                final dur = audioState.duration ?? totalDuration;
                if (dur != null && dur.inMilliseconds > 0) {
                  progress = (audioState.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                }
              }

              // Durée affichée : temps restant si actif, sinon durée totale
              String durationText;
              if (isActive && audioState.duration != null) {
                final remaining = audioState.duration! - audioState.position;
                final remainingSecs = remaining.inSeconds.clamp(0, 9999);
                durationText = '${remainingSecs}s';
              } else {
                durationText = secs != null ? '${secs}s' : '';
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bouton play/pause — CHANGE D'ÉTAT
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
                                duration: const Duration(milliseconds: 80),
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
                        Text(durationText, style: TextStyle(fontSize: 11, color: onSub)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.mic, size: 16, color: onSub),
                ],
              );
            },
          ),
          // Timestamp + coches
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
