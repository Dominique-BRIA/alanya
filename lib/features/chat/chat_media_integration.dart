import 'package:flutter/material.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';
import 'link_bubble.dart';
import 'reply_media_preview.dart';
import 'media_grid.dart';

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
          child: LinkBubble(url: url, meta: snap.data, isMe: mine),
        );
      },
    );
  }

  /// Décide quoi afficher pour un message média :
  /// - 1 média → bulle individuelle (image, vidéo, doc, audio)
  /// - 2+ médias → grille WhatsApp
  /// Retourne null si c'est du texte (pas de média).
  Widget? buildMediaContent(
    Message m, {
    required String baseUrl,
    required String? token,
    required bool isMe,
    required String? timestamp,
    Widget? statusWidget,
    VoidCallback? onTapImage,
    VoidCallback? onTapVideo,
    VoidCallback? onTapFile,
    VoidCallback? onTapAudio,
    VoidCallback? onLongPress,
  }) {
    if (m.media.isEmpty) return null;

    // Multi-médias → grille WhatsApp
    if (m.media.length > 1) {
      return MediaGrid(
        items: m.media.map((media) => MediaGridItem(
          url: media.url,
          mimeType: media.mimeType,
          fileName: media.filename,
          sizeBytes: media.sizeBytes,
          durationMs: media.durationMs,
        )).toList(),
        baseUrl: baseUrl,
        token: token,
        onItemTap: (i) {
          final media = m.media[i];
          final type = MediaHelper.detectType(media.mimeType, media.filename);
          switch (type) {
            case AlanyaMediaType.image: onTapImage?.call(); break;
            case AlanyaMediaType.video: onTapVideo?.call(); break;
            case AlanyaMediaType.audio: onTapAudio?.call(); break;
            default: onTapFile?.call(); break;
          }
        },
        timestamp: timestamp,
        statusWidget: statusWidget,
        isMe: isMe,
      );
    }

    // 1 seul média → pas de grille (retourne null, le _bubble gère)
    return null;
  }
}
