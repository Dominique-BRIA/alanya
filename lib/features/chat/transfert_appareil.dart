/// TRANSFÉRER UN MESSAGE DEPUIS L'APPAREIL — cours, chapitre 29.
///
/// 🐛 « TRANSFÉRER UN MESSAGE DE TOUT TYPE NE DONNE PLUS » (user, 07/10/2026).
/// Le transfert passait par le serveur, qui RECOPIE la ligne du message. Il ne
/// peut pas le faire dès qu'un fil chiffré est en jeu :
///
///   · source chiffrée : il n'a ni le texte, ni la clé du média ;
///   · cible chiffrée : il y écrirait du clair, ce qu'il refuse.
///
/// L'écran écartait donc ces fils, ou le serveur refusait en silence. Le
/// téléphone, lui, a le contenu EN CLAIR : il le renvoie comme un message
/// neuf — chiffré si la cible l'est. C'est ce que fait WhatsApp.
///
/// ⚠️ UN MÉDIA CHIFFRÉ CHANGE DE CLÉ en passant d'un fil à l'autre : il est
/// rechiffré (nouvelle clé, nouveau fichier). Réutiliser la clé d'origine
/// permettrait à quiconque reçoit la copie d'ouvrir l'original, et lierait les
/// deux fils pour le serveur.
library;

import 'dart:typed_data';

import '../../core/message_cache.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../../services/e2ee/e2ee_media_envoi.dart';
import '../media/media_repository.dart';
import 'chat_repository.dart';

/// Le transfert de [m] vers [cible] doit-il passer par l'appareil ?
///
/// Non seulement pour un fil ordinaire vers un autre fil ordinaire : le
/// serveur sait alors recopier la ligne, médias compris, sans retéléverser.
bool transfertParLAppareil(
  Message m, {
  required bool sourceChiffree,
  required bool cibleChiffree,
}) =>
    sourceChiffree || cibleChiffree || m.chiffre || m.mediaChiffre != null;

/// Le correspondant d'un tête-à-tête, vu par [moi] — `null` pour un groupe.
String? correspondantDe(Conversation c, String moi) {
  if (c.isGroup) return null;
  for (final membre in c.members) {
    if (membre.id != moi) return membre.id;
  }
  return null;
}

/// Renvoie [m] dans [cible], depuis le contenu en clair de cet appareil.
///
/// [octetsDuMedia] rend le fichier EN CLAIR du message (déchiffré, ou
/// téléchargé) ; il n'est appelé que si le message porte un média. Lève en
/// cas d'échec : l'appelant le dit.
Future<void> transfererDepuisLAppareil({
  required Message m,
  required Conversation cible,
  required String moi,
  required PileE2ee? pile,
  required ChatRepository chat,
  required MediaRepository medias,
  required Future<({Uint8List octets, String nom, String mime, int? dureeMs})> Function()
      octetsDuMedia,
}) async {
  final texte = m.content ?? '';
  final aUnMedia = m.mediaChiffre != null || m.media.isNotEmpty;
  final pair = cible.e2eeActif ? correspondantDe(cible, moi) : null;
  if (cible.e2eeActif && (pile == null || pair == null)) {
    throw StateError('Conversation chiffrée sans correspondant joignable');
  }

  // ── Un texte, un contact, une position ──
  if (!aUnMedia) {
    if (texte.trim().isEmpty) throw StateError('Rien à transférer');
    if (cible.e2eeActif) {
      final quand = DateTime.now();
      final id = await pile!.fil.envoyer(
          convId: cible.id, pairId: pair!, texte: texte, type: m.type);
      // MA copie : le serveur n'a pas le texte, ce cache et l'archive sont
      // les seuls endroits où il existe pour moi.
      await MessageCache.upsert(
        Message(
          id: id,
          chiffre: true,
          convId: cible.id,
          senderId: moi,
          content: texte,
          type: m.type,
          status: 'SENT',
          replyToId: null,
          media: const [],
          createdAt: quand,
        ),
        cible.id,
      );
      await pile.sauvegarde.deposer([
        {
          'id': id,
          'convId': cible.id,
          'expediteurId': moi,
          'texte': texte,
          'quand': quand.millisecondsSinceEpoch,
          if (m.type != 'TEXT') 'genre': m.type,
        },
      ]);
    } else if (m.type == 'TEXT') {
      await chat.sendText(cible.id, texte);
    } else {
      await chat.sendStructured(cible.id, m.type, texte);
    }
    return;
  }

  // ── Un média : le fichier en clair, renvoyé ──
  final f = await octetsDuMedia();
  if (cible.e2eeActif) {
    await EnvoiMediaChiffre.envoyer(
      pile: pile!,
      medias: medias,
      convId: cible.id,
      pairId: pair!,
      moi: moi,
      fichier: fichierDepuisOctets(f.octets, f.nom, f.mime, dureeMs: f.dureeMs),
      legende: texte,
    );
  } else {
    final envoye = await medias.upload(f.octets, f.nom, f.mime, durationMs: f.dureeMs);
    await chat.sendMultiMedia(cible.id, [envoye.id], typePourMime(f.mime), content: texte);
  }
}

/// Le type de message que le serveur attend pour un fichier de ce type.
String typePourMime(String mime) {
  if (mime.startsWith('image/')) return 'IMAGE';
  if (mime.startsWith('video/')) return 'VIDEO';
  if (mime.startsWith('audio/')) return 'AUDIO';
  return 'FILE';
}
