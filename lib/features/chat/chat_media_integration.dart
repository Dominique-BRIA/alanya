import 'package:flutter/material.dart';
import '../../../core/media_helper.dart';
import '../../../widgets/media/link_bubble.dart';
import '../../../widgets/media/reply_media_preview.dart';
import 'link_preview_integration.dart';

/// Mixin pour les previews média dans chat_screen.dart
mixin ChatMediaIntegrationMixin {
  LinkPreviewIntegration? _linkPreviewIntegration;

  void initMediaIntegration(String baseUrl) {
    _linkPreviewIntegration = LinkPreviewIntegration(baseUrl);
  }

  /// Détecte un lien dans le texte et retourne un LinkBubble.
  Widget buildLinkPreview(String text, bool mine) {
    final url = MediaHelper.extractUrl(text);
    if (url == null) return const SizedBox.shrink();

    return FutureBuilder<LinkMeta?>(
      future: _linkPreviewIntegration?.fetch(url),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinkBubble(
            url: url,
            meta: snap.data,
            isMe: mine,
          ),
        );
      },
    );
  }
}
