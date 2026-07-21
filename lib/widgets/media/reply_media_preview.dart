import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Preview miniature d'un message cité (reply/tag).
/// Affiche un aperçu compact du contenu original.
class ReplyMediaPreview extends StatelessWidget {
  const ReplyMediaPreview({
    super.key,
    required this.replyToContent,
    this.replyToMediaUrl,
    this.replyToMimeType,
    this.replyToFileName,
    this.replyToSenderName,
    this.isMe = false,
  });

  final String? replyToContent;
  final String? replyToMediaUrl;
  final String? replyToMimeType;
  final String? replyToFileName;
  final String? replyToSenderName;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final hasMedia = replyToMediaUrl != null && replyToMediaUrl!.isNotEmpty;
    final type = hasMedia
        ? MediaHelper.detectType(replyToMimeType, replyToFileName)
        : null;

    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? AlanyaColors.terracotta.withValues(alpha: 0.12)
            : AlanyaColors.grey100,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white70 : AlanyaColors.terracotta,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          // Miniature du média
          if (hasMedia) ...[
            _buildThumbnail(type!),
            const SizedBox(width: 8),
          ],
          // Contenu texte
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (replyToSenderName != null)
                  Text(
                    replyToSenderName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isMe ? Colors.white70 : AlanyaColors.terracotta,
                    ),
                  ),
                Text(
                  _previewText(type, replyToContent),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isMe ? Colors.white60 : AlanyaColors.grey600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(AlanyaMediaType type) {
    if (type == AlanyaMediaType.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          replyToMediaUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _miniIcon(type),
        ),
      );
    }
    return _miniIcon(type);
  }

  Widget _miniIcon(AlanyaMediaType type) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: MediaHelper.colorForType(type).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        MediaHelper.iconForType(type),
        size: 20,
        color: MediaHelper.colorForType(type),
      ),
    );
  }

  String _previewText(AlanyaMediaType? type, String? content) {
    if (type != null) {
      switch (type) {
        case AlanyaMediaType.image:
          return '📷 ${content ?? "Photo"}';
        case AlanyaMediaType.video:
          return '🎥 ${content ?? "Vidéo"}';
        case AlanyaMediaType.audio:
          return '🎤 ${content ?? "Audio"}';
        case AlanyaMediaType.pdf:
          return '📄 ${replyToFileName ?? "Document"}';
        case AlanyaMediaType.word:
        case AlanyaMediaType.excel:
        case AlanyaMediaType.powerpoint:
          return '📎 ${replyToFileName ?? "Document"}';
        default:
          return content ?? 'Fichier';
      }
    }
    return content ?? '';
  }
}
