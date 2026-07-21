import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle document — PDF, Word, Excel, PowerPoint, texte.
/// Affiche : icône colorée + nom du fichier + taille + extension.
class DocumentBubble extends StatelessWidget {
  const DocumentBubble({
    super.key,
    required this.url,
    required this.fileName,
    this.fileSize,
    this.mimeType,
    required this.isMe,
    this.onTap,
  });

  final String url;
  final String fileName;
  final int? fileSize;
  final String? mimeType;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = MediaHelper.detectType(mimeType, fileName);
    final icon = MediaHelper.iconForType(type);
    final color = MediaHelper.colorForType(type);
    final ext = MediaHelper.extension(fileName).toUpperCase();
    final size = MediaHelper.formatSize(fileSize);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? AlanyaColors.terracotta.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe
                ? AlanyaColors.terracotta.withValues(alpha: 0.2)
                : AlanyaColors.grey200,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Icône du type de document
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 24),
                  if (ext.isNotEmpty)
                    Text(
                      ext,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Nom + taille
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (size.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      size,
                      style: TextStyle(
                        fontSize: 11,
                        color: AlanyaColors.grey500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Bouton télécharger/ouvrir
            Icon(
              Icons.open_in_new,
              size: 20,
              color: AlanyaColors.grey400,
            ),
          ],
        ),
      ),
    );
  }
}
