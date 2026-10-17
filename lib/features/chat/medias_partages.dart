import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/authed_api.dart';
import '../../core/media_helper.dart';
import '../../core/message_cache.dart';
import '../../core/token_storage.dart';
import '../../models/message.dart';
import '../../services/e2ee/e2ee_media.dart';
import 'chat_repository.dart';
import 'screens/media_gallery_viewer.dart';

/// LES MÉDIAS D'UNE CONVERSATION — un seul chargement pour tous les écrans
/// qui les montrent : la fiche contact (bande d'aperçus), « Médias partagés »
/// et la galerie plein écran.
///
/// 🐛 POURQUOI CE FICHIER (user, 03/10/2026). Chaque écran avait sa copie du
/// chargement, et chacune avait les mêmes trois défauts :
///
///   1. le jeton lu AVANT les messages, alors que ce chargement le
///      rafraîchit s'il a expiré — chaque vignette partait avec un jeton
///      mort (401) ;
///   2. une seule page de 50 messages : les médias plus anciens
///      n'apparaissaient jamais ;
///   3. les médias chiffrés ignorés, ou pire, affichés tels quels — c'est-à-
///      dire le fichier illisible du serveur.
///
/// « Médias partagés » avait été corrigé, la fiche contact non : c'est
/// exactement ce qu'une copie produit.
class FilPourMedias {
  FilPourMedias(this.messages, this.descripteurs, this.token);

  /// Du plus récent au plus ancien, toutes pages lues.
  final List<Message> messages;

  /// Les clés des médias chiffrés, par identifiant de message. Elles ne sont
  /// que sur ce téléphone (cache local).
  final Map<String, DescripteurMedia> descripteurs;

  /// Le jeton lu APRÈS les messages : celui que l'application vient, au
  /// besoin, de renouveler.
  final String? token;

  /// Le descripteur du média chiffré de [m], s'il est connu.
  DescripteurMedia? chiffreDe(Message m) => m.mediaChiffre ?? descripteurs[m.id];
}

/// Au plus tant de pages de 100 messages : une longue conversation, sans
/// faire d'un écran d'aperçus un téléchargement sans fin.
const pagesMaxMedias = 30;

Future<FilPourMedias> chargerFilPourMedias(
  BuildContext context,
  String convId,
) async {
  final repo = context.read<ChatRepository>();
  final storage = context.read<TokenStorage>();
  AuthedApi? api;
  try {
    api = context.read<AuthedApi>();
  } catch (_) {}

  final messages = <Message>[];
  String? curseur;
  for (var p = 0; p < pagesMaxMedias; p++) {
    final page = await repo.getMessages(convId, cursor: curseur, limit: 100);
    messages.addAll(page);
    if (page.length < 100) break;
    curseur = page.last.id;
  }

  final token = api != null ? await api.jeton() : await storage.accessToken;
  final descripteurs = <String, DescripteurMedia>{
    for (final m in await MessageCache.getConv(convId))
      if (m.mediaChiffre != null) m.id: m.mediaChiffre!,
  };
  return FilPourMedias(messages, descripteurs, token);
}

/// Les médias que le téléphone connaît DÉJÀ : les messages de son cache
/// local, sans un seul appel réseau.
///
/// 🐛 « LES MÉDIAS SONT CHARGÉS INDÉFINIMENT » (user, 10/10/2026).
/// [chargerFilPourMedias] lit jusqu'à 30 pages de 100 messages avant de rien
/// rendre ; les écrans attendaient tout. Ils affichent maintenant ceci
/// d'abord, puis le complètent avec le réseau.
Future<FilPourMedias> filPourMediasEnCache(
  BuildContext context,
  String convId,
) async {
  final storage = context.read<TokenStorage>();
  final messages = [...await MessageCache.getConv(convId)]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return FilPourMedias(messages, const {}, await storage.accessToken);
}

/// Les photos et vidéos de [messages], prêtes pour la galerie — en clair ou
/// chiffrées. Une vue unique n'y figure jamais : elle ne s'ouvre qu'une fois,
/// dans son visionneur protégé. Un média chiffré dont ce téléphone n'a pas la
/// clé non plus : il n'y aurait rien à montrer.
List<ConvMediaItem> mediasGalerie(
  Iterable<Message> messages, {
  required String baseUrl,
  required String? token,
  DescripteurMedia? Function(Message m)? chiffreDe,
}) {
  final items = <ConvMediaItem>[];
  for (final msg in messages) {
    if (msg.vueUnique || msg.isDeleted) continue;
    for (final media in msg.media) {
      if (media.chiffre) {
        final d = chiffreDe != null ? chiffreDe(msg) : msg.mediaChiffre;
        if (d == null) continue;
        final video = d.mime.startsWith('video/');
        if (!video && !d.mime.startsWith('image/')) continue;
        items.add(ConvMediaItem(
          id: d.id,
          url: '',
          downloadUrl: '',
          filename: d.nom ?? '',
          isVideo: video,
          chiffre: d,
        ));
        continue;
      }
      final t = MediaHelper.detectType(media.mimeType, media.filename);
      if (t == AlanyaMediaType.image || t == AlanyaMediaType.video) {
        items.add(ConvMediaItem(
          id: media.id,
          url: '$baseUrl${media.url}?token=${token ?? ''}',
          downloadUrl: '$baseUrl${media.url}?download=1&token=${token ?? ''}',
          filename: media.filename ?? '',
          isVideo: t == AlanyaMediaType.video,
        ));
      }
    }
  }
  return items;
}
