import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Preview miniature d'un message cité (reply) — style WhatsApp :
/// - Barre colorée à gauche
/// - Nom de l'expéditeur en gras
/// - Pour les images : miniature thumbnail
/// - Pour les vidéos : miniature + icône play
/// - Pour les documents : icône type + nom
/// - Pour le texte : aperçu du texte
class ReplyMediaPreview extends StatelessWidget {
  const ReplyMediaPreview({
    super.key,
    required this.replyToContent,
    this.replyToMediaUrl,
    this.replyToMimeType,
    this.replyToFileName,
    this.replyToSenderName,
    this.replyToThumbnailUrl,
    this.isMe = false,
    this.onTap,
  });

  final String? replyToContent;
  final String? replyToMediaUrl;
  final String? replyToMimeType;
  final String? replyToFileName;
  final String? replyToSenderName;
  final String? replyToThumbnailUrl;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasMedia = replyToMediaUrl != null && replyToMediaUrl!.isNotEmpty;
    final type = hasMedia
        ? MediaHelper.detectType(replyToMimeType, replyToFileName)
        : null;
    final barColor = isMe ? Colors.white70 : AlanyaColors.terracotta;
    final onColor = isMe ? Colors.white : AlanyaColors.ink;
    final onSub = isMe ? Colors.white60 : Colors.black54;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.1)
              : AlanyaColors.sand.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: barColor, width: 3),
          ),
        ),
        child: Row(
          children: [
            // Miniature média (si image/vidéo)
            if (hasMedia && type == AlanyaMediaType.image)
              _buildImageThumbnail()
            else if (hasMedia && type == AlanyaMediaType.video)
              _buildVideoThumbnail()
            else if (hasMedia)
              _buildDocIcon(type!),

            if (hasMedia) const SizedBox(width: 8),

            // Contenu texte
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nom expéditeur
                  if (replyToSenderName != null)
                    Text(
                      replyToSenderName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: barColor,
                      ),
                    ),
                  // Texte preview
                  Text(
                    _previewText(type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: onSub,
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

  /// Miniature image (40x40 arrondi).
  Widget _buildImageThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        replyToMediaUrl!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _miniIcon(AlanyaMediaType.image),
      ),
    );
  }

  /// Miniature vidéo (40x40 avec play overlay).
  Widget _buildVideoThumbnail() {
    final thumb = replyToThumbnailUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          if (thumb != null)
            Image.network(
              thumb,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _miniIcon(AlanyaMediaType.video),
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

  /// Icône document (40x40).
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
            MediaHelper.extension(replyToFileName).toUpperCase().replaceAll('.', ''),
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
          return replyToContent ?? 'Photo';
        case AlanyaMediaType.video:
          return replyToContent ?? 'Vidéo';
        case AlanyaMediaType.audio:
          return 'Message vocal';
        case AlanyaMediaType.pdf:
          return replyToFileName ?? 'Document';
        case AlanyaMediaType.word:
        case AlanyaMediaType.excel:
        case AlanyaMediaType.powerpoint:
          return replyToFileName ?? 'Document';
        default:
          return replyToContent ?? 'Fichier';
      }
    }
    return replyToContent ?? '';
  }
}
