import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../theme/alanya_theme.dart';

/// Bulle vidéo style WhatsApp :
/// - Vraie thumbnail générée depuis l'URL vidéo (si pas de thumbnail serveur)
/// - Bouton play central (cercle blanc + triangle)
/// - Durée badge en bas à gauche
/// - Timestamp + coches en bas à droite
class VideoBubble extends StatefulWidget {
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

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  Uint8List? _thumbnailBytes;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  @override
  void didUpdateWidget(VideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) return;
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final url = widget.token != null
          ? '${widget.videoUrl}?token=${widget.token}'
          : widget.videoUrl;
      final thumb = await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 75,
      );
      if (mounted && thumb != null) setState(() => _thumbnailBytes = thumb);
    } catch (_) {} finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '';
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasThumbUrl = widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty;
    final thumbUrl = hasThumbUrl && widget.token != null
        ? '${widget.thumbnailUrl}?token=${widget.token}'
        : widget.thumbnailUrl;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: widget.width,
          height: widget.maxHeight.clamp(200, 280),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasThumbUrl)
                Image.network(thumbUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder())
              else if (_thumbnailBytes != null)
                Image.memory(_thumbnailBytes!, fit: BoxFit.cover)
              else
                _placeholder(),

              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
                  ),
                ),
              ),

              Center(
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF1B1B1B), size: 30),
                ),
              ),

              if (widget.duration != null && widget.duration! > 0)
                Positioned(
                  left: 8, bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.videocam, color: Colors.white, size: 12),
                      const SizedBox(width: 3),
                      Text(_formatDuration(widget.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),

              if (widget.timestamp != null)
                Positioned(
                  right: 6, bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.timestamp!, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      if (widget.statusWidget != null) ...[
                        const SizedBox(width: 3),
                        widget.statusWidget!,
                      ],
                    ]),
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
      child: const Center(child: Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 48)),
    );
  }
}
