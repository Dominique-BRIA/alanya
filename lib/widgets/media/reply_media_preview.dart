import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Preview miniature d'un message cité (reply) — style WhatsApp.
/// Pour les vidéos : génère une thumbnail via video_thumbnail.
class ReplyMediaPreview extends StatefulWidget {
  const ReplyMediaPreview({
    super.key,
    required this.replyToContent,
    this.replyToMediaUrl,
    this.replyToMimeType,
    this.replyToFileName,
    this.replyToSenderName,
    this.isMe = false,
    this.onTap,
  });

  final String? replyToContent;
  final String? replyToMediaUrl;
  final String? replyToMimeType;
  final String? replyToFileName;
  final String? replyToSenderName;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  State<ReplyMediaPreview> createState() => _ReplyMediaPreviewState();
}

class _ReplyMediaPreviewState extends State<ReplyMediaPreview> {
  Uint8List? _videoThumb;

  @override
  void initState() {
    super.initState();
    _generateVideoThumb();
  }

  bool get _isVideo {
    final mime = widget.replyToMimeType ?? '';
    return mime.startsWith('video/');
  }

  bool get _isImage {
    final mime = widget.replyToMimeType ?? '';
    return mime.startsWith('image/');
  }

  Future<void> _generateVideoThumb() async {
    if (!_isVideo || widget.replyToMediaUrl == null) return;
    try {
      final thumb = await VideoThumbnail.thumbnailData(
        video: widget.replyToMediaUrl!,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 100,
        quality: 60,
      );
      if (mounted && thumb != null) setState(() => _videoThumb = thumb);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = widget.replyToMediaUrl != null && widget.replyToMediaUrl!.isNotEmpty;
    final type = hasMedia
        ? MediaHelper.detectType(widget.replyToMimeType, widget.replyToFileName)
        : null;
    final barColor = widget.isMe ? Colors.white70 : AlanyaColors.terracotta;
    final onSub = widget.isMe ? Colors.white60 : Colors.black54;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.1)
              : AlanyaColors.sand.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: barColor, width: 3),
          ),
        ),
        child: Row(
          children: [
            // Miniature
            if (hasMedia && _isImage)
              _buildImageThumbnail()
            else if (hasMedia && _isVideo)
              _buildVideoThumbnail()
            else if (hasMedia)
              _buildDocIcon(type!),

            if (hasMedia) const SizedBox(width: 8),

            // Texte
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.replyToSenderName != null)
                    Text(
                      widget.replyToSenderName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: barColor,
                      ),
                    ),
                  Text(
                    _previewText(type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: onSub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Miniature image (40x40 arrondi).
  Widget _buildImageThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        widget.replyToMediaUrl!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _miniIcon(AlanyaMediaType.image),
      ),
    );
  }

  /// Miniature vidéo (40x40 avec play overlay) — utilise video_thumbnail
  Widget _buildVideoThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          if (_videoThumb != null)
            Image.memory(
              _videoThumb!,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            )
          else
            Container(
              width: 40,
              height: 40,
              color: const Color(0xFF2A2A2A),
              child: const Icon(Icons.movie, color: Colors.white38, size: 18),
            ),
          // Mini play
          Positioned.fill(
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, size: 10, color: Color(0xFF1B1B1B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocIcon(AlanyaMediaType type) {
    return _miniIcon(type);
  }

  Widget _miniIcon(AlanyaMediaType type) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: MediaHelper.colorForType(type).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            MediaHelper.iconForType(type),
            size: 18,
            color: MediaHelper.colorForType(type),
          ),
          Text(
            MediaHelper.extension(widget.replyToFileName).toUpperCase().replaceAll('.', ''),
            style: TextStyle(
              fontSize: 6,
              fontWeight: FontWeight.w800,
              color: MediaHelper.colorForType(type),
            ),
          ),
        ],
      ),
    );
  }

  String _previewText(AlanyaMediaType? type) {
    if (type != null) {
      switch (type) {
        case AlanyaMediaType.image:
          return widget.replyToContent ?? 'Photo';
        case AlanyaMediaType.video:
          return widget.replyToContent ?? 'Vidéo';
        case AlanyaMediaType.audio:
          return 'Message vocal';
        case AlanyaMediaType.pdf:
          return widget.replyToFileName ?? 'Document';
        case AlanyaMediaType.word:
        case AlanyaMediaType.excel:
        case AlanyaMediaType.powerpoint:
          return widget.replyToFileName ?? 'Document';
        default:
          return widget.replyToContent ?? 'Fichier';
      }
    }
    return widget.replyToContent ?? '';
  }
}
