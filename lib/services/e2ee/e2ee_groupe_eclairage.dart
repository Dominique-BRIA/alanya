/// OUVRIR LES MESSAGES D'UN GROUPE CHIFFRÉ — la règle, en un seul endroit.
///
/// 🐛 UN GROUPE CHIFFRÉ N'AVAIT AUCUN APERÇU DANS LA LISTE tant qu'on ne
/// l'avait pas ouvert sur CET appareil (trouvé le 12/10/2026, en vérifiant à la
/// demande du user que le chiffrement des groupes n'avait rien cassé).
///
/// 🔴 LA CAUSE, ET POURQUOI ELLE NE TOUCHE QUE LES GROUPES. Un message de
/// tête-à-tête voyage dans une ENVELOPPE, et la relève de fond les ramène
/// toutes, quel que soit le fil affiché : le cache se remplit tout seul. Le
/// corps d'un message de GROUPE, lui, est posé sur le message et ne se
/// déchiffre qu'en chargeant les messages de ce fil. Sans ouverture, rien
/// n'arrive dans le cache, et la liste n'a rien à montrer.
///
/// 🔴 CE FICHIER EXISTE POUR QU'IL N'Y AIT PAS DEUX COPIES DE LA RÈGLE. Elle
/// vivait dans l'écran de discussion ; la liste en avait besoin aussi. Deux
/// copies, et l'une des deux oublierait un jour de ranger le média, ou la
/// réponse, ou de retirer l'attente de clé.
///
/// ⚠️ RIEN NE SE CONSOMME : le chiffré reste sur le serveur et se relit à
/// chaque chargement, avec le trousseau du coffre. Le cache sert l'affichage
/// immédiat et hors ligne, comme pour un message en clair.
library;

import 'dart:async';

import '../../core/message_cache.dart';
import '../../models/message.dart';
import 'e2ee_fournisseur.dart';
import 'e2ee_groupe_fil.dart' show EchecGroupe;

/// Ce qu'une ouverture a donné.
class EclairageGroupe {
  const EclairageGroupe({required this.messages, required this.attenteCle});

  /// La page, chaque message de groupe remplacé par sa version en clair quand
  /// elle a pu être obtenue.
  final List<Message> messages;

  /// Les identifiants dont la clé du groupe n'est pas encore sur cet appareil :
  /// leur bulle dit « en attente de la clé du groupe », et non « indisponible ».
  final Set<String> attenteCle;
}

/// Ouvre les messages de groupe de [page] et range leur clair dans le cache.
///
/// ⚠️ UN ÉCHEC LAISSE LE MESSAGE TEL QUEL (clé pas encore reçue, signature
/// refusée) : l'écran affiche « indisponible sur cet appareil ». Jamais de
/// texte deviné.
///
/// ⚠️ NE LÈVE JAMAIS : un groupe illisible ne doit pas empêcher d'afficher les
/// autres, ni la liste de s'afficher.
Future<EclairageGroupe> ouvrirMessagesGroupe({
  required PileE2ee pile,
  required String convId,
  required List<Message> page,
}) async {
  if (!page.any((m) => m.chiffreGroupe != null)) {
    return EclairageGroupe(messages: page, attenteCle: const {});
  }
  final sortie = <Message>[];
  final attente = <String>{};
  for (final m in page) {
    final c = m.chiffreGroupe;
    if (c == null || m.isDeleted) {
      sortie.add(m);
      continue;
    }
    try {
      final (clair, echec) = await pile.fil.groupe.lire(
        convId: convId,
        messageId: m.id,
        expediteurId: m.senderId,
        chiffre: c,
      );
      if (clair == null) {
        if (echec == EchecGroupe.cleAbsente) attente.add(m.id);
        sortie.add(m);
        continue;
      }
      sortie.add(m.avecDechiffre(texte: clair.texte, media: clair.media));
      unawaited(MessageCache.rangeTexteDechiffre(
        id: m.id,
        convId: convId,
        expediteurId: m.senderId,
        texte: clair.texte,
        quand: m.createdAt,
        media: clair.media,
        genre: clair.genre,
        replyToId: clair.reponseA,
      ).then((_) {}, onError: (_) {}));
    } catch (_) {
      sortie.add(m);
    }
  }
  return EclairageGroupe(messages: sortie, attenteCle: attente);
}
