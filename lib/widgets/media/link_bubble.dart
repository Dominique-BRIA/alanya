import 'package:flutter/material.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/alanya_theme.dart';

/// Bulle de preview de lien style WhatsApp — utilise any_link_preview.
/// Affiche automatiquement : image, titre, description, nom du site.
/// Tout côté client, pas besoin de backend.
class LinkBubble extends StatelessWidget {
  const LinkBubble({
    super.key,
    required this.url,
    this.isMe = false,
    this.maxWidth = 260,
  });

  final String url;
  final bool isMe;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.15)
                : AlanyaColors.grey200,
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnyLinkPreview(
          link: url,
          displayDirection: UIDirection.uiDirectionVertical,
          showMultimedia: true,
          cache: const Duration(hours: 1),
          backgroundColor: isMe
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: 10,
          removeElevation: true,
          bodyMaxLines: 2,
          bodyTextOverflow: TextOverflow.ellipsis,
          titleStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isMe ? Colors.white : AlanyaColors.ink,
          ),
          bodyStyle: TextStyle(
            fontSize: 12,
            color: isMe ? Colors.white60 : Colors.black54,
          ),
          errorWidget: Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.link, size: 18, color: isMe ? Colors.white60 : AlanyaColors.grey500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe ? Colors.white60 : AlanyaColors.terracotta,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
