/// LE DERNIER MESSAGE D'UN FIL CHIFFRÉ, DANS LA LISTE DES CONVERSATIONS.
///
/// Fonction PURE, éprouvée par `test/dernier_message_local_test.dart`.
library;

import '../../models/conversation.dart';
import '../../models/message_payload.dart' show apercuStructure;

/// Remplace l'aperçu des fils CHIFFRÉS par le dernier texte connu localement.
///
/// 🐛 DEMANDE DU USER, 28/09/2026 : dans la liste, un fil chiffré n'affichait
/// pas son dernier message. Le serveur ne connaît pas ce texte — c'est tout le
/// principe — et rend donc `lastMessage: null` ; la liste retombait sur
/// l'aperçu du dernier appel, ou sur rien.
///
/// Le texte, lui, EXISTE sur l'appareil : la relève range chaque message
/// déchiffré dans le cache de SON fil, et nos propres messages y sont rangés
/// à l'envoi. [locaux] donne, par conversation, le plus récent d'entre eux.
///
/// ⚠️ LE SERVEUR GAGNE S'IL EST PLUS RÉCENT. Un fil chiffré peut avoir reçu
/// un MÉDIA après le dernier texte : les pièces jointes ne sont pas chiffrées,
/// le serveur en connaît le libellé (« 📷 Photo ») — et c'est bien lui le
/// dernier message.
///
/// ⚠️ LES FILS ORDINAIRES NE SONT PAS TOUCHÉS : le serveur y a le texte.
///
/// ⚠️ LE COMPTEUR DE NON-LUS NE VIENT PAS D'ICI : le serveur l'incrémente
/// aussi pour un message chiffré (il sait qu'un message est arrivé, pas ce
/// qu'il dit).
List<Conversation> appliquerDerniersTextes(
  List<Conversation> convs,
  Map<String, LastMessage> locaux,
) =>
    [
      for (final c in convs)
        if (!c.e2eeActif || locaux[c.id] == null)
          c
        else if (_serveurPlusRecent(c.lastMessage, locaux[c.id]!))
          c
        else
          c.copieAvecDernier(_lisible(locaux[c.id]!)),
    ];

/// Un contact ou une position chiffrés sont rangés en JSON : la liste montre
/// leur libellé (« 👤 Jean »), comme le serveur le fait pour un fil clair.
LastMessage _lisible(LastMessage m) {
  final libelle = apercuStructure(m.type, m.content);
  if (libelle == null) return m;
  return LastMessage(
    id: m.id,
    content: libelle,
    type: m.type,
    senderId: m.senderId,
    createdAt: m.createdAt,
  );
}

bool _serveurPlusRecent(LastMessage? serveur, LastMessage local) {
  if (serveur == null) return false;
  // Sans texte, l'aperçu du serveur n'apprend rien : c'est un message chiffré
  // dont il n'a que la ligne.
  if ((serveur.content ?? '').isEmpty) return false;
  return serveur.createdAt.isAfter(local.createdAt);
}
