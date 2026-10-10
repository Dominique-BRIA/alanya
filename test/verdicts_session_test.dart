import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/api_client.dart';
import 'package:alanya/core/authed_api.dart';
import 'package:alanya/core/token_storage.dart';
import 'package:alanya/core/verdicts_session.dart';
import 'package:alanya/core/verrou_rafraichissement.dart';
import 'package:alanya/features/auth/auth_controller.dart';

/// LA BOUCLE DE 401 DU 10/10/2026, rejouée sans téléphone.
///
/// Le cas réel : l'installation d'un APK tue l'application à la seconde où
/// elle tourne son jeton ; rouverte 1 h 42 plus tard, elle présente l'ancien.
/// Le serveur refuse. Avant ce correctif : refus anonyme, gardé comme un doute,
/// et chaque écran relançait un renouvellement — ~1 200 requêtes en dix
/// minutes, sans jamais revenir à l'écran de connexion.
///
/// Lancer avec : flutter test test/verdicts_session_test.dart

/// Un serveur dont chaque route répond 401, et le renouvellement [refus].
class _ServeurQuiRefuse extends ApiClient {
  _ServeurQuiRefuse(this.refus) : super(baseUrl: "http://banc");
  final ApiException refus;
  int renouvellements = 0;
  int requetes = 0;

  @override
  Future<Map<String, dynamic>> get(String path, {String? bearer}) async {
    requetes++;
    // Laisse les appels concurrents se rejoindre sur le même renouvellement.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    throw ApiException(401, "Non authentifié", "UNAUTHORIZED");
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {String? bearer}) async {
    if (path == "/api/auth/refresh") {
      renouvellements++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      throw refus;
    }
    throw ApiException(401, "Non authentifié", "UNAUTHORIZED");
  }
}

/// Des jetons en mémoire : le vrai stockage passe par un canal de plateforme.
class _JetonsEnMemoire extends TokenStorage {
  @override
  Future<String?> get accessToken async => "acces-perime";
  @override
  Future<String?> get refreshToken async => "renouvellement-deja-tourne";
  @override
  Future<void> saveTokens({required String access, required String refresh}) async {}
}

Future<void> _dixEcransEnMemeTemps(AuthedApi api) => Future.wait(
      List.generate(10, (i) => api.get("/api/ecran/$i").then((_) {}, onError: (_) {})),
    );

void main() {
  setUp(VerrouRafraichissement.reinitialiserPourTest);

  group("Le verdict du serveur remonte jusqu'à la session", () {
    test("JETON_DEJA_TOURNE ferme la session (au démarrage comme en usage)", () {
      expect(
        sessionMorteApresEchec(ApiException(401, "Session à rouvrir", "JETON_DEJA_TOURNE")),
        isTrue,
      );
    });

    test("un message l'explique, sans parler d'intrusion", () {
      final m = messageFermeture("JETON_DEJA_TOURNE");
      expect(m, isNotNull);
      expect(m, isNot(contains("autre appareil")));
      expect(m, isNot(contains("sécurité")));
    });

    test("les messages existants n'ont pas bougé", () {
      expect(messageFermeture("SESSION_EVINCEE"), "Votre compte a été ouvert sur un autre appareil.");
      expect(messageFermeture("JETON_REJOUE"), "Session fermée par sécurité. Reconnecte-toi.");
      expect(messageFermeture("SESSION_REVOQUEE"), isNull);
      expect(messageFermeture("BAD_REFRESH"), isNull);
    });

    test("dix écrans en 401 : UN renouvellement, UN verdict signalé", () async {
      final serveur = _ServeurQuiRefuse(
          ApiException(401, "Session à rouvrir", "JETON_DEJA_TOURNE"));
      final api = AuthedApi(serveur, _JetonsEnMemoire());
      final recus = <ApiException>[];
      final ecoute = VerdictsSession.flux.listen(recus.add);

      await _dixEcransEnMemeTemps(api);
      await Future<void>.delayed(Duration.zero);

      expect(serveur.requetes, 10);
      expect(serveur.renouvellements, 1);
      expect(recus.map((e) => e.code), ["JETON_DEJA_TOURNE"]);
      await ecoute.cancel();
    });
  });

  group("🔴 Plus de renouvellement en boucle", () {
    test("après un échec, les 401 suivants ne relancent PAS de renouvellement",
        () async {
      // Refus ANONYME : le cas où l'on garde la session — c'est lui qui
      // tournait en rond.
      final serveur = _ServeurQuiRefuse(
          ApiException(401, "Refresh token invalide", "BAD_REFRESH"));
      final api = AuthedApi(serveur, _JetonsEnMemoire());

      await _dixEcransEnMemeTemps(api);
      await _dixEcransEnMemeTemps(api);
      await _dixEcransEnMemeTemps(api);

      expect(serveur.requetes, 30);
      expect(serveur.renouvellements, 1,
          reason: "avant le correctif : un renouvellement par vague d'écrans");
    });

    test("le délai grandit puis plafonne à une minute", () {
      expect(delaiAvantNouvelEssai(0), Duration.zero);
      expect(delaiAvantNouvelEssai(1), const Duration(seconds: 5));
      expect(delaiAvantNouvelEssai(2), const Duration(seconds: 10));
      expect(delaiAvantNouvelEssai(3), const Duration(seconds: 20));
      expect(delaiAvantNouvelEssai(4), const Duration(seconds: 40));
      expect(delaiAvantNouvelEssai(5), const Duration(seconds: 60));
      expect(delaiAvantNouvelEssai(50), const Duration(seconds: 60));
    });
  });
}
