import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle de preview de lien — style WhatsApp/Telegram.
/// Affiche : image OG, titre, description, nom du site.
class LinkBubble extends StatelessWidget {
  const LinkBubble({
    super.key,
    required this.url,
    this.meta,
    required this.isMe,
    this.maxWidth = 260,
    this.onTap,
  });

  final String url;
  final LinkMeta? meta;
  final bool isMe;
  final double maxWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasMeta = meta != null;
    final siteName = meta?.siteName ?? _extractDomain(url);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: isMe
              ? AlanyaColors.terracotta.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe
                ? AlanyaColors.terracotta.withValues(alpha: 0.2)
                : AlanyaColors.grey200,
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image OG
            if (hasMeta && meta!.imageUrl != null)
              Image.network(
                meta!.imageUrl!,
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),

            // Contenu texte
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nom du site
                  Row(
                    children: [
                      Icon(Icons.language, size: 14, color: AlanyaColors.grey500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          siteName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AlanyaColors.grey500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hasMeta && meta!.title != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta!.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (hasMeta && meta!.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta!.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AlanyaColors.grey600,
                      ),
                    ),
                  ],
                  // URL cliquable
                  const SizedBox(height: 6),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AlanyaColors.terracotta,
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
