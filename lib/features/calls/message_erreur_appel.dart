import '../../core/api_client.dart';

/// Traduit en une phrase l'échec du démarrage d'un appel.
///
/// Point unique, et c'est la raison d'être de ce fichier : les trois écrans qui
/// peuvent lancer un appel — le fil de discussion, la fiche de contact et le
/// clavier — traitaient l'erreur chacun de leur côté, avec trois variantes
/// incomplètes. Depuis le fil, la clause `on ApiException` manquait : appeler
/// quelqu'un déjà en ligne affichait « Erreur d'appel : vérifie ta connexion »
/// alors que le serveur disait précisément « Le correspondant est déjà en
/// appel ». Le même appel depuis le clavier donnait la bonne phrase.
///
/// ⚠️ **Le message du serveur passe tel quel.** C'est lui qui sait pourquoi
/// l'appel est refusé, et il distingue des cas que le client ne peut pas
/// deviner — « Vous êtes déjà en appel » (409 BUSY) et « Le correspondant est
/// déjà en appel » (409 CALLEE_BUSY) ne se ressemblent que par leur code.
///
/// [messageSi404] : le clavier cherche un compte par son Alanya ID, un 404 y
/// signifie « ce numéro n'existe pas ». Depuis une conversation déjà ouverte,
/// ce cas n'a pas le même sens — d'où le paramètre plutôt qu'une phrase figée.
String messageErreurAppel(Object erreur, {String? messageSi404}) {
  // Levée par le contrôleur avant tout appel réseau : un appel est déjà en
  // cours SUR CET APPAREIL.
  if (erreur is StateError) return "Tu es déjà en appel";

  if (erreur is ApiException) {
    if (erreur.statusCode == 404 && messageSi404 != null) return messageSi404;
    return erreur.message;
  }

  final texte = erreur.toString();
  if (texte.contains("PERMISSION_DENIED")) {
    return "Micro/caméra requis. Accorde les permissions dans les réglages.";
  }
  // Repli : un 409 remonté autrement que par une ApiException. Rare, mais le
  // message générique serait trompeur — il parlerait de connexion réseau.
  if (texte.contains("409") || texte.contains("BUSY")) {
    return "Impossible de démarrer l'appel. Réessaie dans un instant.";
  }
  return "Erreur d'appel : vérifie ta connexion et réessaie.";
}
