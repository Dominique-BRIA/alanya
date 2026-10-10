import 'dart:async';

import 'api_client.dart';

/// LES REFUS DE RENOUVELLEMENT, remontés de [AuthedApi] jusqu'à
/// `AuthController` — qui seul décide du sort de la session.
///
/// 🐛 POURQUOI CE CANAL (10/10/2026). `AuthedApi` avalait toute erreur de
/// renouvellement (« on ne juge pas ici »)… et plus personne ne jugeait ensuite.
/// Seul le DÉMARRAGE lisait le verdict du serveur. Une session condamnée en
/// cours d'utilisation ne ramenait donc jamais à l'écran de connexion : chaque
/// écran prenait un 401, retentait, reprenait un 401. Vu sur un téléphone :
/// ~1 200 requêtes en dix minutes, et « Impossible de contacter le serveur »
/// affiché à un utilisateur dont le serveur répondait très bien.
///
/// ⚠️ ON SIGNALE TOUT, ON NE TRIE PAS ICI. La règle « ce refus tue-t-il la
/// session ? » vit dans `sessionMorteApresEchec`, à un seul endroit ; la
/// recopier dans la couche réseau, c'est préparer le jour où les deux listes
/// divergeront.
class VerdictsSession {
  VerdictsSession._();

  static final _flux = StreamController<ApiException>.broadcast();

  /// Chaque refus NOMMÉ ou non du serveur à un renouvellement.
  static Stream<ApiException> get flux => _flux.stream;

  static void signaler(ApiException e) => _flux.add(e);
}

/// Combien attendre avant de retenter un renouvellement, après [echecs]
/// échecs consécutifs qui n'ont PAS condamné la session (réseau coupé, 502,
/// refus anonyme).
///
/// 5 s, 10 s, 20 s, 40 s, puis une minute au plus.
///
/// ⚠️ SANS CE DÉLAI, CHAQUE REQUÊTE EN 401 RELANÇAIT UN RENOUVELLEMENT : la
/// boucle de rafraîchissement d'un écran (3 s) suffisait à envoyer un
/// renouvellement voué à l'échec toutes les trois secondes, sans fin.
///
/// ⚠️ PLAFONNÉ À UNE MINUTE, PAS DAVANTAGE : un 502 pendant un redéploiement
/// dure quelques secondes, et l'utilisateur ne doit pas attendre cinq minutes
/// que l'application ose redemander.
Duration delaiAvantNouvelEssai(int echecs) {
  if (echecs <= 0) return Duration.zero;
  final secondes = 5 * (1 << (echecs - 1).clamp(0, 4));
  return Duration(seconds: secondes > 60 ? 60 : secondes);
}
