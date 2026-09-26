import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/api_client.dart';
import 'package:alanya/features/auth/auth_controller.dart';

/// Spécification exécutable d'UNE règle : **quand efface-t-on la session ?**
///
/// 🔴 POURQUOI CE FICHIER. Le user a signalé le 26/08/2026 des « déconnexions
/// intempestives » sur le web comme sur le mobile. Ce n'étaient pas deux
/// défauts sans rapport : les deux clients confondaient « le serveur a REFUSÉ
/// mon jeton » avec « je n'ai pas pu joindre le serveur », et détruisaient la
/// session dans les deux cas.
///
/// Côté mobile, toute panne du rafraîchissement au démarrage tombait dans
/// « Échec total », qui appelle `_storage.clear()`. Une coupure réseau, un 502
/// pendant un redéploiement, un lancement hors ligne : la session était perdue
/// et il fallait retaper son mot de passe.
///
/// ⚠️ CES CONTRÔLES PORTENT SUR LA RÈGLE, PAS SUR L'ÉCRAN. `bootstrap()` ne se
/// teste pas — ses dépendances sont des classes concrètes adossées aux canaux
/// de plateforme (`flutter_secure_storage`). C'est précisément pour cela que la
/// règle a été sortie dans une fonction pure : c'est le seul niveau où elle est
/// vraie une fois pour toutes.
///
/// Lancer avec : flutter test test/session_expiration_test.dart
void main() {
  group("Le serveur a NOMMÉ sa décision — la session est morte", () {
    test("SESSION_EVINCEE : compte ouvert sur un autre appareil", () {
      expect(
        sessionMorteApresEchec(
            ApiException(401, "Session fermée", "SESSION_EVINCEE")),
        isTrue,
      );
    });

    test("JETON_REJOUE : un jeton copié a circulé", () {
      expect(
        sessionMorteApresEchec(
            ApiException(401, "Fermée par sécurité", "JETON_REJOUE")),
        isTrue,
      );
    });

    test("SESSION_REVOQUEE : fermée depuis « Appareils connectés »", () {
      expect(
        sessionMorteApresEchec(
            ApiException(401, "Session révoquée", "SESSION_REVOQUEE")),
        isTrue,
      );
    });

    test("le code décide, pas le statut HTTP", () {
      // Le même code sur un 403 ferme tout autant : c'est la DÉCISION du
      // serveur qui compte, et elle s'écrit dans le code.
      expect(
        sessionMorteApresEchec(
            ApiException(403, "Session fermée", "SESSION_EVINCEE")),
        isTrue,
      );
    });
  });

  group("🔴 Le 4xx ANONYME ne ferme plus rien — la régression corrigée", () {
    // C'est LE défaut : « déconnecté alors que mon jeton n'était pas expiré ».
    // La rotation révoque l'ancien jeton à CHAQUE rafraîchissement, donc tout
    // réessai tombait sur un 401 `BAD_REFRESH` — et l'ancienne règle, qui
    // fermait sur n'importe quel 4xx, détruisait la session.
    test("401 BAD_REFRESH : un jeton déjà tourné, donc un simple réessai", () {
      expect(
        sessionMorteApresEchec(
            ApiException(401, "Refresh token invalide", "BAD_REFRESH")),
        isFalse,
      );
    });

    test("401 sans code : le serveur n'a rien nommé, on garde", () {
      expect(sessionMorteApresEchec(ApiException(401, "Non autorisé")), isFalse);
    });

    test("400 : une requête mal formée ne dit rien du jeton", () {
      expect(sessionMorteApresEchec(ApiException(400, "Requête invalide")),
          isFalse);
    });

    test("un code inconnu d'un serveur plus récent ne ferme pas", () {
      // ⚠️ LES CLIENTS NE SE METTENT PAS À JOUR EN MÊME TEMPS. Un APK ancien
      // face à un code qu'il ne connaît pas doit GARDER la session : au pire
      // il réessaiera, au lieu de déconnecter sur un mot qu'il ne comprend pas.
      expect(
        sessionMorteApresEchec(ApiException(401, "?", "QUELQUE_CHOSE_DE_NEUF")),
        isFalse,
      );
    });
  });

  group("Le serveur n'a rien jugé — on GARDE la session", () {
    test("500 : le serveur est tombé", () {
      expect(sessionMorteApresEchec(ApiException(500, "Erreur serveur")),
          isFalse);
    });

    test("502 : Nginx pendant un redéploiement", () {
      // Le cas le plus fréquent, et le plus injuste : on redéploie, et tous les
      // clients dont le jeton d'accès venait d'expirer perdaient leur session.
      expect(sessionMorteApresEchec(ApiException(502, "Bad Gateway")), isFalse);
    });

    test("503 : le serveur redémarre", () {
      expect(sessionMorteApresEchec(ApiException(503, "Indisponible")), isFalse);
    });

    test("réseau coupé : SocketException, et non ApiException", () {
      // ⚠️ CE CAS N'EST PAS UNE ApiException, et c'est ce qui le rendait
      // invisible : il ne passait pas par la branche qui inspectait le statut.
      expect(sessionMorteApresEchec(const SocketException("pas de route")),
          isFalse);
    });

    test("délai dépassé", () {
      expect(sessionMorteApresEchec(TimeoutException()), isFalse);
    });

    test("n'importe quoi d'autre : dans le doute, on garde", () {
      // Une session gardée à tort se corrige au rafraîchissement suivant ; une
      // session détruite à tort oblige à retaper son mot de passe et fait
      // perdre le cache hors ligne. L'asymétrie décide.
      expect(sessionMorteApresEchec(Exception("inattendu")), isFalse);
      expect(sessionMorteApresEchec("une chaîne"), isFalse);
    });
  });

  group("🔴 IL N'Y A PLUS DE FRONTIÈRE PAR STATUT", () {
    // L'ancienne règle disait « tout 4xx tue » : 499 fermait la session, 399
    // non. Cette frontière était le défaut lui-même — elle rangeait le réessai
    // le plus banal (401 `BAD_REFRESH`) du côté des condamnations.
    //
    // Le statut ne décide plus de rien. Seul le CODE nommé par le serveur
    // décide, et il n'y en a que quatre.
    for (final statut in [399, 400, 401, 403, 409, 499, 500, 502, 0]) {
      test("$statut sans code nommé ne ferme rien", () {
        expect(sessionMorteApresEchec(ApiException(statut, "?")), isFalse);
      });
    }

    test("la liste des verdicts fait exactement quatre entrées", () {
      // ⚠️ GARDE-FOU : élargir cette liste, c'est réintroduire des
      // déconnexions. Toute entrée nouvelle doit être une décision que le
      // serveur prend et NOMME — jamais une commodité.
      expect(codesSessionFermee, hasLength(4));
    });
  });
}

/// Une panne de délai, telle que `http` la remonte.
class TimeoutException implements Exception {
  @override
  String toString() => "délai dépassé";
}
