/// L'ÉTAT D'UN MESSAGE ENVOYÉ NE REDESCEND JAMAIS.
///
/// Fonctions PURES, éprouvées par `test/statut_envoi_test.dart`.
library;

/// Le rang d'un état : plus il est haut, plus le message est avancé.
///
/// En attente, envoyé et en échec ne disent rien de ce qu'a fait le
/// destinataire : ils partagent le rang 0.
int rangStatut(String statut) {
  switch (statut) {
    case 'READ':
      return 2;
    case 'DELIVERED':
      return 1;
    default:
      return 0;
  }
}

/// L'état à afficher quand la réponse du serveur remplace la bulle provisoire.
///
/// 🐛 « L'ÉTAT DE MON MESSAGE NE SE MET PLUS À JOUR » (user, 28/09/2026,
/// mobile). Une COURSE : le serveur prévient le destinataire AVANT d'attendre
/// la notification push de Google, et ne répond à l'expéditeur qu'APRÈS. Un
/// destinataire qui a la conversation ouverte lit donc le message, et l'écran
/// de l'expéditeur reçoit « lu » alors que sa bulle attend encore. Puis la
/// réponse arrive, et la bulle était remplacée par une bulle « envoyé » : la
/// double coche bleue redevenait une coche simple, pour toujours — le
/// destinataire ayant déjà lu, plus rien ne viendrait la corriger.
///
/// ⚠️ LA COURSE EST PLUS ANCIENNE QUE « ENVOYER SANS ATTENDRE » (8f8b3ea).
/// Avant, la bulle n'était créée qu'après la réponse : le « lu » arrivé plus
/// tôt ne trouvait aucune bulle à marquer, avec le même résultat. C'est au
/// contraire parce que la bulle existe désormais PENDANT l'envoi que le « lu »
/// peut s'y poser — et cette fonction le garde.
String statutFusionne({required String affiche, required String recu}) =>
    rangStatut(recu) >= rangStatut(affiche) ? recu : affiche;
