import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../widgets/media/link_bubble.dart';
import '../../widgets/media/reply_media_preview.dart';

/// Mixin pour les previews média dans chat_screen.dart
mixin ChatMediaIntegrationMixin {
  /// Appelé dans _load() — plus besoin de backend pour les previews.
  void initMediaIntegration(String baseUrl) {
    // no-op : any_link_preview fonctionne côté client
  }

  /// Détecte un lien dans le texte et retourne un LinkBubble.
  Widget buildLinkPreview(String text, bool mine) {
    final url = MediaHelper.extractUrl(text);
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LinkBubble(url: url, isMe: mine),
    );
  }
}
