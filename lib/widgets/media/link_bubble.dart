import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle lien style WhatsApp :
/// - Image OG en haut (pleine largeur) si disponible
/// - Ligne site (icône globe + nom du site)
/// - Titre en gras
/// - Description (1-2 lignes)
/// - URL en bas (couleur terracotta)
/// - Bordure subtile, coins arrondis
class LinkBubble extends StatelessWidget {
  const LinkBubble({
    super.key,
    required this.url,
    this.meta,
    this.isMe = false,
    this.maxWidth = 260,
    this.onTap,
    this.onLongPress,
  });

  final String url;
  final LinkMeta? meta;
  final bool isMe;
  final double maxWidth;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final hasMeta = meta != null;
    final siteName = meta?.siteName ?? _extractDomain(url);
    final onText = isMe ? Colors.white : AlanyaColors.ink;
    final onSub = isMe ? Colors.white60 : Colors.black54;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.15)
                : AlanyaColors.grey200,
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image OG (pleine largeur)
            if (hasMeta && meta!.imageUrl != null)
              Image.network(
                meta!.imageUrl!,
                width: double.infinity,
                height: 130,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),

            // Contenu texte
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nom du site (icône globe + nom)
                  Row(
                    children: [
                      Icon(Icons.language, size: 13, color: onSub),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          siteName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: onSub,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Titre
                  if (hasMeta && meta!.title != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      meta!.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: onText,
                        height: 1.3,
                      ),
                    ),
                  ],

                  // Description
                  if (hasMeta && meta!.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta!.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: onSub,
                        height: 1.3,
                      ),
                    ),
                  ],

                  // URL
                  const SizedBox(height: 6),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe ? Colors.white54 : AlanyaColors.terracotta,
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

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}
