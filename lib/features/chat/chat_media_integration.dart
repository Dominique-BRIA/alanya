import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../widgets/media/link_bubble.dart';
import '../../widgets/media/reply_media_preview.dart';

/// Mixin pour les previews média dans chat_screen.dart
mixin ChatMediaIntegrationMixin {
  /// Détecte un lien dans le texte et retourne un LinkBubble.
  /// Utilise any_link_preview (côté client, pas de backend).
  Widget buildLinkPreview(String text, bool mine) {
    final url = MediaHelper.extractUrl(text);
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LinkBubble(url: url, isMe: mine),
    );
  }
}
