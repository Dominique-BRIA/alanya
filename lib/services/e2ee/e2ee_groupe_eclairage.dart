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
import 'dart:convert';

import '../../core/message_cache.dart';
import '../../models/message.dart';
import 'e2ee_fournisseur.dart';
import 'e2ee_groupe_fil.dart' show EchecGroupe;
import 'e2ee_media.dart' show DescripteurMedia;

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
  // v2 (lot 3) : ce groupe a peut-être des membres à qui il manque des
  // emballages (nouveau venu, nouvelle clé de compte, migration) ; cet appareil
  // les complète s'il a les clés. En arrière-plan, une fois par demi-minute.
  unawaited(pile.fil.groupe.rattraper(convId));
  final sortie = <Message>[];
  final attente = <String>{};
  /*
   * 🔁 LE CACHE D'ABORD (11/11/2026, lot 1 du chiffrement des groupes v2).
   * Ce qui a déjà été déchiffré une fois sur cet appareil n'est plus jamais
   * redéchiffré : c'était le coût de chaque ouverture de groupe et de chaque
   * aperçu de liste. Un message MODIFIÉ, lui, a un nouveau chiffré : il est
   * toujours relu. L'expéditeur de la ligne en cache doit être le même.
   */
  final candidats = [
    for (final m in page)
      if (m.chiffreGroupe != null && !m.isDeleted && m.editedAt == null) m.id,
  ];
  var connus = const <String, ({String texte, String expediteurId, String? mediaJson})>{};
  try {
    connus = await MessageCache.clairsConnus(convId, candidats);
  } catch (_) {
    // Cache illisible : on retombe sur le déchiffrement, comme avant.
  }
  for (final m in page) {
    final c = m.chiffreGroupe;
    if (c == null || m.isDeleted) {
      sortie.add(m);
      continue;
    }
    final connu = m.editedAt == null ? connus[m.id] : null;
    if (connu != null && connu.expediteurId == m.senderId) {
      DescripteurMedia? media;
      try {
        if (connu.mediaJson != null) media = DescripteurMedia.depuisJson(jsonDecode(connu.mediaJson!));
      } catch (_) {}
      sortie.add(m.avecDechiffre(texte: connu.texte, media: media));
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
