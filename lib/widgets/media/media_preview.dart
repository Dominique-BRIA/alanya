import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import 'image_bubble.dart';
import 'video_bubble.dart';
import 'document_bubble.dart';
import 'link_bubble.dart';
import 'audio_bubble.dart';

/// Widget principal qui dispatch vers le bon renderer selon le type de média.
///
/// Utilisation :
/// ```dart
/// MediaPreview(
///   mediaUrl: message.mediaUrl,
///   mimeType: message.mediaMimeType,
///   fileName: message.mediaName,
///   fileSize: message.mediaSizeBytes,
///   duration: message.mediaDuration,
///   isMe: isMe,
/// )
/// ```
class MediaPreview extends StatelessWidget {
  const MediaPreview({
    super.key,
    this.mediaUrl,
    this.mimeType,
    this.fileName,
    this.fileSize,
    this.duration,
    this.thumbnailUrl,
    this.isMe = false,
    this.maxWidth = 260,
    this.maxHeight = 300,
    this.onTap,
    this.linkMeta,
    this.linkUrl,
  });

  final String? mediaUrl;
  final String? mimeType;
  final String? fileName;
  final int? fileSize;
  final int? duration;
  final String? thumbnailUrl;
  final bool isMe;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback? onTap;
  final LinkMeta? linkMeta;
  final String? linkUrl;

  @override
  Widget build(BuildContext context) {
    // Priorité 1 : lien URL (preview OG)
    if (linkUrl != null || linkMeta != null) {
      return LinkBubble(
        meta: linkMeta,
        url: linkUrl ?? '',
        isMe: isMe,
        maxWidth: maxWidth,
        onTap: onTap,
      );
    }

    final type = MediaHelper.detectType(mimeType, fileName);

    switch (type) {
      case AlanyaMediaType.image:
        return ImageBubble(
          url: mediaUrl!,
          isMe: isMe,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          onTap: onTap,
        );
      case AlanyaMediaType.video:
        return VideoBubble(
          url: mediaUrl!,
          thumbnailUrl: thumbnailUrl,
          duration: duration,
          isMe: isMe,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          onTap: onTap,
        );
      case AlanyaMediaType.audio:
        return AudioBubble(
          url: mediaUrl!,
          duration: duration,
          isMe: isMe,
          onTap: onTap,
        );
      case AlanyaMediaType.pdf:
      case AlanyaMediaType.word:
      case AlanyaMediaType.excel:
      case AlanyaMediaType.powerpoint:
      case AlanyaMediaType.text:
      case AlanyaMediaType.unknown:
        return DocumentBubble(
          url: mediaUrl!,
          fileName: fileName ?? 'Fichier',
          fileSize: fileSize,
          mimeType: mimeType,
          isMe: isMe,
          onTap: onTap,
        );
    }
  }
}
