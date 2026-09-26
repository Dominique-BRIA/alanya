/// LA RÈGLE D'OUVERTURE D'UNE CONVERSATION, HORS DE L'ÉCRAN.
///
/// 🔴 POURQUOI CE FICHIER EXISTE. L'écran de conversation enchaînait trois
/// attentes — le cache local, le jeton du coffre sécurisé, le serveur — et
/// aucune n'était bornée ni contrôlée. Il en restait un chargement infini dès
/// que l'une d'elles ne répondait pas : la roue tournait sur un fil dont on
/// connaissait déjà le contenu, ou sur un vide que rien n'expliquait.
///
/// ⚠️ LA RÈGLE EST ICI PARCE QU'ELLE EST LE SEUL NIVEAU TESTABLE. `_load()` ne
/// se teste pas : ses dépendances sont adossées aux canaux de plateforme
/// (`flutter_secure_storage`, `sqflite`) et à un arbre de widgets. Même raison
/// que `sessionMorteApresEchec` pour l'expiration de session : on sort la
/// décision, on la rend vraie une fois pour toutes, l'écran n'applique plus.
///
/// Lancer avec : flutter test test/ouverture_conversation_test.dart
library;

import '../models/message.dart';

/// Ce que l'écran doit rendre à l'issue d'une ouverture de conversation.
class IssueOuverture {
  const IssueOuverture({
    required this.messages,
    required this.cacheAReecrire,
    required this.enPanne,
  });

  /// Les messages à afficher — ceux du serveur s'il a répondu, sinon ceux du
  /// cache. Une liste peut être vide ; elle ne peut pas être « on ne sait pas ».
  final List<Message> messages;

  /// Vrai quand [messages] vient du serveur, et de lui seul.
  ///
  /// ⚠️ LE CACHE N'EST RÉÉCRIT QUE SUR UNE RÉPONSE. `putConv` efface la
  /// conversation avant de réinsérer : y pousser une liste née d'un timeout
  /// effacerait l'historique connu pour une simple coupure réseau.
  final bool cacheAReecrire;

  /// Vrai quand il n'y a RIEN à montrer et que le serveur n'a pas répondu.
  ///
  /// 🔴 C'EST LE CAS QUI FAIT LA DIFFÉRENCE ENTRE UNE PANCHE ET UNE ROUE. Un
  /// fil vide parce que la conversation l'est se dit « aucun message » ; un fil
  /// vide parce qu'on n'a pas pu le charger se dit « réessayez ». Rendre la
  /// roue qui tourne dans les deux cas est ce qui rendait le défaut sans issue.
  final bool enPanne;
}

/// Décide de ce que rend l'écran, d'après ce que cache et serveur ont bien
/// voulu rendre.
///
/// [recus] vaut `null` quand le serveur n'a RIEN rendu : erreur, délai dépassé,
/// avion coupé. Ce `null` est la donnée importante de la fonction : c'est lui
/// qui distingue « le fil est vide » de « le fil n'est pas arrivé » — une liste,
/// rendue vide, ne le dit pas.
///
/// ⚠️ UN FIL QUE LE SERVEUR ANNONCE VIDE EST VRAIMENT VIDE, et le cache doit le
/// suivre : c'est le chemin par lequel une suppression pour tous les membres
/// atteint les appareils. Ne pas réécrire là laisserait relire, à chaque
/// ouverture, des messages que quelqu'un a effacés.
IssueOuverture decideOuverture({
  required List<Message> caches,
  List<Message>? recus,
}) {
  if (recus == null) {
    // Rien de neuf : on rend ce qu'on sait, et on ne touche à rien d'autre.
    return IssueOuverture(
      messages: caches,
      cacheAReecrire: false,
      // Le « réessayez » n'a de sens que devant un écran vide. Avec du
      // contenu sous les yeux, l'utilisateur lit son fil — c'est déjà tout ce
      // qu'il demandait — et le bandeau global « hors ligne » est allumé.
      enPanne: caches.isEmpty,
    );
  }
  return IssueOuverture(
    messages: recus,
    cacheAReecrire: true,
    enPanne: false,
  );
}
