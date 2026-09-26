/// DE QUI VIENT UN ÉCHEC DE CONNEXION — et, jusqu'ici, rien ne le disait.
///
/// 🔴 LE DÉFAUT CORRIGÉ ICI N'EST PAS RÉSEAU, IL EST DE LANGUE. Partout dans
/// l'authentification, le même moule :
///
///     } on ApiException catch (e) { showAppSnackBar(e.message); }
///     catch (_) { showAppSnackBar(tr(context, 'server_unreachable')); }
///
/// Un `ApiException` est le SEUL cas où l'on sait que le serveur a répondu :
/// c'est lui qui porte un code de statut. Tout le reste tombe dans le `catch (_)`
/// et hérite de « Impossible de contacter le serveur » — y compris quand le
/// serveur a parfaitement répondu :
///
///   • `HandshakeException` : il répond, mais son certificat est refusé par
///     Android. Cas réel et fréquent quand Nginx sert le certificat sans la
///     chaîne d'intermédiaires — le navigateur la complète tout seul (AIA),
///     `dart:io` non. Le user voit « serveur injoignable » sur un serveur vivant.
///   • `TypeError` : réponse 200 dans un format que `AuthUser.fromJson` ne sait
///     pas lire — exactement ce qu'un déploiement backend qui change un champ
///     produit. Le message accuse alors le réseau, pas le contrat.
///   • `TimeoutException` : la requête est partie, rien ne revient. Le serveur
///     est joignable, il ne répond pas — ce n'est pas la même réparation.
///   • une écriture dans le coffre sécurisé qui échoue : le compte est ouvert,
///     c'est l'appareil qui refuse de le retenir.
///
/// ⚠️ LE COÛT DE CE MENSONGE N'EST PAS ESTHÉTIQUE : il envoie l'utilisateur
/// vérifier sa box au lieu de faire réparer le certificat, et il envoie le
/// développeur relire `ApiClient` au lieu de relire le déploiement.
///
/// ⚠️ DEUX TECHNIQUES, ET LE CHOIX N'EST PAS COSMÉTIQUE :
///
///   • `ApiException` est reconnu par `is` — c'est une classe de CE projet, pure
///     Dart, et un `is` survit à un renommage, ce qu'une chaîne ne fait pas.
///   • les erreurs de pile réseau sont reconnues PAR NOM ET PAR TEXTE, et non par
///     `is SocketException` : `dart:io` n'existe pas dans une compilation web, et
///     ce fichier doit rester lisible des deux côtés — c'est à lui de traduire
///     l'erreur, pas à l'erreur de le choisir. Le prix est connu : un nom de type
///     change un jour, et ce fichier retombe alors sur `local`, jamais sur un
///     faux accusé. `test/connexion_classifiee_test.dart` construit les vraies
///     exceptions pour dire si ce prix vient d'être payé.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'api_client.dart';

/// Les natures d'un échec, dans l'ordre de ce qu'elles impliquent.
enum NatureEchec {
  /// Rien n'est sorti de l'appareil : DNS, route, port fermé, serveur arrêté.
  injoignable,

  /// Le serveur est là, c'est la poignée de main TLS qui a échoué.
  tls,

  /// La requête est partie, aucune réponse dans le délai.
  sansReponse,

  /// Une réponse est bien arrivée — mais pas celle attendue.
  reponseInattendue,

  /// Ce n'est pas le réseau : c'est l'appareil (coffre, base, droits).
  local,
}

/// Devine la nature de l'échec à partir de ce que la machine en a dit.
///
/// ⚠️ L'ORDRE DES TESTS EST LE FOND DU SUJET, et la raison est concrète :
/// `package:http` rattrape l'erreur de pile et la relance en `ClientException`
/// dont le MESSAGE recopie le texte d'origine. Un certificat refusé arrive donc
/// typé `ClientException` — la famille « réseau » — et ne se reconnaît qu'à son
/// texte (`CERTIFICATE_VERIFY_FAILED`). Trier par le type avant le texte
/// classerait toute panne de certificat en « serveur injoignable » : exactement
/// le défaut qu'on est en train de nommer. Le texte passe donc AVANT le type.
NatureEchec natureEchec(Object e) {
  final type = e.runtimeType.toString();
  final brut = e.toString();

  // 🔴 TESTÉ EN PREMIER : une `ApiException` prouve que le serveur a RÉPONDU —
  // c'est la seule erreur de tout ce classement qui porte un code de statut. Le
  // dire « injoignable » serait exactement le mensonge qu'on corrige ici.
  if (e is ApiException) return NatureEchec.reponseInattendue;

  if (type.contains('Handshake') ||
      brut.contains('HandshakeException') ||
      brut.contains('certificate') ||
      brut.contains('CERTIFICATE')) {
    return NatureEchec.tls;
  }
  if (e is TimeoutException) return NatureEchec.sansReponse;

  if (type.contains('SocketException') ||
      type == 'ClientException' ||
      brut.contains('Failed host lookup') ||
      brut.contains('Connection refused') ||
      brut.contains('Connection reset') ||
      brut.contains('Network is unreachable')) {
    return NatureEchec.injoignable;
  }

  if (e is FormatException ||
      type.contains('TypeError') ||
      type.contains('CastError')) {
    return NatureEchec.reponseInattendue;
  }

  // ⚠️ LE REPLI EST ICI, ET IL EST CHOISI : dans le doute, on accuse
  // l'appareil — jamais le serveur. Un « serveur injoignable » non mérité fait
  // perdre une journée à quelqu'un d'autre ; un « l'application n'a pas pu
  // terminer » lui fait retenter dix secondes.
  return NatureEchec.local;
}

/// La clé du catalogue à afficher pour cet échec.
///
/// ⚠️ UNE CLÉ, PAS UN TEXTE : les neuf langues portent déjà `server_unreachable`,
/// et la règle de parité (`l10n_parite_test.dart`) veille sur les nouvelles.
String cleEchecDe(Object e) => switch (natureEchec(e)) {
      NatureEchec.injoignable => 'server_unreachable',
      NatureEchec.tls => 'tls_error',
      NatureEchec.sansReponse => 'server_no_answer',
      NatureEchec.reponseInattendue => 'unexpected_answer',
      NatureEchec.local => 'device_error',
    };

/// Le détail brut, pour `adb logcat`.
///
/// 🔴 LE JOURNAL N'EST PAS UN ORNEMENT : le texte montré au user reste court et
/// sans jargon, à dessein. Le seul endroit où un défaut de chaîne de certificats
/// ou un champ manquant dans une réponse devient réparable, c'est la ligne-ci-
/// dessous dans le journal — et sans elle, le diagnostic se fait par ouï-dire.
void traceEchecConnexion(Object e) {
  debugPrint('[CONNEXION] nature=${natureEchec(e).name} '
      'type=${e.runtimeType} detail=$e');
}
