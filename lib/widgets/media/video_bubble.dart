import 'package:flutter/material.dart';
import '../../theme/alanya_theme.dart';

/// Bulle vidéo style WhatsApp :
/// - Thumbnail (ou placeholder sombre si pas de thumbnail)
/// - Bouton play central (cercle blanc + triangle)
/// - Durée badge en bas à gauche
/// - Timestamp + coches en bas à droite
class VideoBubble extends StatelessWidget {
  const VideoBubble({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.token,
    this.duration,
    this.width = 274,
    this.maxHeight = 280,
    this.onTap,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final String? token;
  final int? duration;
  final double width;
  final double maxHeight;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '';
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = thumbnailUrl != null && token != null
        ? '$thumbnailUrl?token=$token'
        : thumbnailUrl;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: width,
          height: maxHeight.clamp(200, 280),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail ou placeholder
              if (thumbUrl != null)
                Image.network(
                  thumbUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              else
                _placeholder(),

              // Overlay sombre léger
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),

              // Bouton play central (WhatsApp style : cercle blanc transparent + triangle)
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Color(0xFF1B1B1B),
                    size: 30,
                  ),
                ),
              ),

              // Durée badge en bas à gauche
              if (duration != null && duration! > 0)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam, color: Colors.white, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Timestamp + coches en bas à droite
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
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Center(
        child: Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 48),
      ),
    );
  }
}
