import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/media_helper.dart';
import '../../../widgets/media/link_bubble.dart';
import '../../../widgets/media/media_picker_sheet.dart';
import '../../../widgets/media/reply_media_preview.dart';
import '../../../features/media/link_preview_repository.dart';

/// Extension sur ChatScreenState pour ajouter les previews média.
/// 
/// Dans chat_screen.dart, ajouter :
///   import '../chat_media_integration.dart';
/// 
/// Et dans _ChatScreenState :
///   final _mediaIntegration = ChatMediaIntegration();
///   Dans initState : _mediaIntegration.init(baseUrl);
mixin ChatMediaIntegrationMixin {
  LinkPreviewRepository? _linkPreviewRepo;
  
  void initMediaIntegration(String baseUrl) {
    _linkPreviewRepo = LinkPreviewRepository(baseUrl);
  }

  /// Détecte un lien dans le texte et retourne un widget de preview.
  Widget buildLinkPreview(String text, bool mine) {
    final url = MediaHelper.extractUrl(text);
    if (url == null) return const SizedBox.shrink();
    
    return FutureBuilder<LinkMeta?>(
      future: _linkPreviewRepo?.fetch(url),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LinkBubble(
            url: url,
            meta: snap.data,
            isMe: mine,
            onTap: () => _launchLink(url),
          ),
        );
      },
    );
  }

  /// Bouton pour ouvrir le sélecteur de médias.
  Widget buildMediaPickerButton(BuildContext context, Function(List<MediaPickResult>) onPicked) {
    return IconButton(
      icon: Icon(Icons.attach_file, color: Colors.grey.shade600),
      onPressed: () async {
        final files = await MediaPickerSheet.show(context);
        if (files != null && files.isNotEmpty) {
          onPicked(files);
        }
      },
    );
  }

  /// Preview du message cité (reply).
  Widget buildReplyPreview({
    required String? replyToContent,
    required String? replyToMediaUrl,
    required String? replyToMimeType,
    required String? replyToFileName,
    required String? replyToSenderName,
    required bool isMe,
  }) {
    return ReplyMediaPreview(
      replyToContent: replyToContent,
      replyToMediaUrl: replyToMediaUrl,
      replyToMimeType: replyToMimeType,
      replyToFileName: replyToFileName,
      replyToSenderName: replyToSenderName,
      isMe: isMe,
    );
  }

  Future<void> _launchLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
