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
  group("Le serveur a JUGÉ le jeton — la session est morte", () {
    test("401 : jeton expiré ou invalide", () {
      expect(sessionMorteApresEchec(ApiException(401, "Non autorisé")), isTrue);
    });

    test("403 : session évincée par une connexion ailleurs", () {
      expect(
        sessionMorteApresEchec(
            ApiException(403, "Session fermée", "SESSION_EVINCEE")),
        isTrue,
      );
    });

    test("400 : le serveur refuse la demande de rafraîchissement", () {
      expect(sessionMorteApresEchec(ApiException(400, "Requête invalide")),
          isTrue);
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

  group("La frontière est bien à 400 et à 500", () {
    test("399 ne tue pas", () {
      expect(sessionMorteApresEchec(ApiException(399, "?")), isFalse);
    });
    test("499 tue encore", () {
      expect(sessionMorteApresEchec(ApiException(499, "?")), isTrue);
    });
    test("0 — statut des pannes réseau côté web — ne tue pas", () {
      expect(sessionMorteApresEchec(ApiException(0, "injoignable")), isFalse);
    });
  });
}

/// Une panne de délai, telle que `http` la remonte.
class TimeoutException implements Exception {
  @override
  String toString() => "délai dépassé";
}
