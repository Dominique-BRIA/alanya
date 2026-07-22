import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle document style WhatsApp :
/// - Ligne 1 : icône colorée (extension) + nom du fichier + taille
/// - Ligne 2 : timestamp + coches
/// - Coins arrondis, fond coloré selon le type
/// - Tap = ouvrir/télécharger
class DocumentBubble extends StatelessWidget {
  const DocumentBubble({
    super.key,
    required this.fileName,
    this.fileSize,
    this.mimeType,
    this.onTap,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final String fileName;
  final int? fileSize;
  final String? mimeType;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final type = MediaHelper.detectType(mimeType, fileName);
    final icon = MediaHelper.iconForType(type);
    final color = MediaHelper.colorForType(type);
    final ext = MediaHelper.extension(fileName).toUpperCase().replaceAll('.', '');
    final size = MediaHelper.formatSize(fileSize);
    final onText = isMe ? Colors.white : AlanyaColors.ink;
    final onSub = isMe ? Colors.white70 : Colors.black45;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne : icône + nom + taille
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icône colorée avec extension
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isMe ? Colors.white.withValues(alpha: 0.15) : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: isMe ? Colors.white : color, size: 22),
                    if (ext.isNotEmpty)
                      Text(
                        ext,
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          color: isMe ? Colors.white70 : color,
                          letterSpacing: 0.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Nom + taille
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onText,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (size.isNotEmpty) ...[
                          Text(size,
                              style: TextStyle(fontSize: 11, color: onSub)),
                          Text('  ·  ', style: TextStyle(fontSize: 11, color: onSub)),
                        ],
                        Text(
                          ext.isNotEmpty ? '$ext Document' : 'Document',
                          style: TextStyle(fontSize: 11, color: onSub),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Icône download
              Icon(
                Icons.file_download_outlined,
                color: isMe ? Colors.white60 : AlanyaColors.grey500,
                size: 22,
              ),
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
