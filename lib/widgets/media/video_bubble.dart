import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle vidéo — thumbnail avec bouton play et durée.
class VideoBubble extends StatelessWidget {
  const VideoBubble({
    super.key,
    required this.url,
    this.thumbnailUrl,
    this.duration,
    required this.isMe,
    this.maxWidth = 260,
    this.maxHeight = 300,
    this.onTap,
  });

  final String url;
  final String? thumbnailUrl;
  final int? duration;
  final bool isMe;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Thumbnail
              if (thumbnailUrl != null)
                Image.network(
                  thumbnailUrl!,
                  fit: BoxFit.cover,
                  width: maxWidth,
                  height: maxHeight,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              else
                _placeholder(),

              // Overlay sombre
              Container(
                width: maxWidth,
                height: maxHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.4),
                    ],
                  ),
                ),
              ),

              // Bouton play
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
              ),

              // Durée en bas à droite
              if (duration != null && duration! > 0)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      MediaHelper.formatDuration(duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
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
      width: maxWidth,
      height: 200,
      color: isMe
          ? AlanyaColors.terracotta.withValues(alpha: 0.15)
          : AlanyaColors.grey200,
      child: Icon(Icons.videocam, color: AlanyaColors.grey400, size: 48),
    );
  }
}
