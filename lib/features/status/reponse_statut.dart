import 'dart:async';
import 'dart:typed_data';

import '../../core/message_cache.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../../services/e2ee/e2ee_media_envoi.dart';
import '../../widgets/media/media_picker_sheet.dart' show MediaPickResult;
import '../chat/chat_repository.dart';
import '../media/media_repository.dart';

/// RÉPONDRE À UN STATUT — par écrit ou de vive voix — dans le tête-à-tête avec
/// son auteur, en citant le statut.
///
/// 🐛 DANS UN FIL CHIFFRÉ, LA RÉPONSE ÉCHOUAIT (user, 01/11/2026). Elle
/// partait toujours en clair, et le serveur refuse le clair dans une
/// conversation chiffrée (`CONVERSATION_CHIFFREE`) : l'écran disait « réponse
/// non envoyée ». Elle passe maintenant par le chemin chiffré quand le fil
/// l'est — et la citation part avec : le serveur la recopie depuis le statut,
/// qu'il connaît déjà, sans rien lire du message.
///
/// ⚠️ JAMAIS DE REPLI EN CLAIR si le chiffrement échoue : on lève, l'écran le
/// dit. Même règle que la discussion.
class ReponseStatut {
  ReponseStatut._();

  static Future<void> envoyer({
    required ChatRepository chat,
    required MediaRepository medias,
    required PileE2ee? pile,
    required String? moi,
    required String auteurId,
    required String statutId,
    String? texte,
    ({Uint8List octets, int dureeMs})? vocal,
  }) async {
    assert((texte == null) != (vocal == null));
    final conv = await chat.getOrCreateDirectConversation(auteurId);
    final convId = conv["id"] as String;

    // ÉTAT INCONNU → ON DEMANDE AVANT D'ENVOYER, comme la discussion : un fil
    // jamais ouvert sur cet appareil partirait sinon en clair.
    if (pile != null && !pile.fil.etatConnu(convId)) {
      try {
        await pile.fil.etat(convId);
      } catch (_) {
        // Hors d'atteinte : le serveur tranchera, et refusera le clair.
      }
    }

    if (pile == null || !pile.fil.estChiffree(convId)) {
      if (texte != null) {
        await chat.sendText(convId, texte, statutCite: statutId);
      } else {
        final media = await medias.upload(vocal!.octets, 'reponse-statut.m4a', 'audio/mp4',
            durationMs: vocal.dureeMs);
        await chat.sendMedia(convId, media.id, 'AUDIO', statutCite: statutId);
      }
      return;
    }

    if (moi == null) throw StateError('Compte inconnu : envoi chiffré impossible.');

    if (vocal != null) {
      // Chiffré, téléversé, et MA COPIE rangée — comme un vocal de la discussion.
      await EnvoiMediaChiffre.envoyer(
        pile: pile,
        medias: medias,
        convId: convId,
        pairId: auteurId,
        moi: moi,
        fichier: MediaPickResult(
          bytes: vocal.octets,
          fileName: 'reponse-statut.m4a',
          mimeType: 'audio/mp4',
          durationMs: vocal.dureeMs,
        ),
        statutCite: statutId,
      );
      return;
    }

    final quand = DateTime.now();
    final id = await pile.fil.envoyer(
      convId: convId,
      pairId: auteurId,
      texte: texte!,
      statutCite: statutId,
    );
    /*
     * ⚠️ MA COPIE DU CLAIR : aucune enveloppe ne m'est adressée, et le serveur
     * ne garde que la ligne sans texte. Sans le cache et l'archive, ma propre
     * réponse s'afficherait vide en ouvrant la discussion.
     */
    await MessageCache.rangeTexteDechiffre(
      id: id,
      convId: convId,
      expediteurId: moi,
      texte: texte,
      quand: quand,
    );
    unawaited(pile.sauvegarde.deposer([
      {
        'id': id,
        'convId': convId,
        'expediteurId': moi,
        'texte': texte,
        'quand': quand.millisecondsSinceEpoch,
      },
    ]));
  }
}
