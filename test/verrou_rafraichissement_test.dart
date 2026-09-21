import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/verrou_rafraichissement.dart';

/// Spécification exécutable d'UNE règle : **deux rafraîchissements lancés en
/// même temps n'en déclenchent qu'un seul.**
///
/// 🔴 POURQUOI CETTE RÈGLE EST CRITIQUE. Le serveur fait TOURNER le jeton de
/// rafraîchissement : chaque appel révoque l'ancien. Deux appels concurrents
/// avec le même jeton, et le second se voit refuser — ce que le client prenait
/// pour « la session est morte ». L'utilisateur était déconnecté alors que rien
/// n'avait expiré.
///
/// Un verrou existait, mais il vivait dans `AuthedApi` et ne couvrait pas
/// `AuthController.bootstrap()`. Au démarrage — le moment où tout part
/// ensemble — les deux chemins se rafraîchissaient en parallèle.
///
/// Lancer avec : flutter test test/verrou_rafraichissement_test.dart
void main() {
  setUp(VerrouRafraichissement.reinitialiserPourTest);

  test("deux appels concurrents ne font qu'UN seul travail", () async {
    var appels = 0;
    final porte = Completer<void>();

    Future<String?> travail() async {
      appels++;
      await porte.future;
      return "jeton-neuf";
    }

    // Lancés AVANT toute attente : c'est la situation réelle, deux chemins qui
    // démarrent dans le même tour de boucle.
    final a = VerrouRafraichissement.partage(travail);
    final b = VerrouRafraichissement.partage(travail);
    porte.complete();

    expect(await a, "jeton-neuf");
    expect(await b, "jeton-neuf");
    expect(appels, 1, reason: "le second appel doit REJOINDRE le premier");
  });

  test("le verrou se libère : un appel ultérieur retravaille", () async {
    var appels = 0;
    Future<String?> travail() async {
      appels++;
      return "jeton-$appels";
    }

    expect(await VerrouRafraichissement.partage(travail), "jeton-1");
    // ⚠️ SANS CETTE LIBÉRATION, la session ne se rafraîchirait plus JAMAIS :
    // tout le monde attendrait éternellement le premier résultat, périmé.
    expect(await VerrouRafraichissement.partage(travail), "jeton-2");
    expect(appels, 2);
  });

  test("un échec libère le verrou, et se propage à tous les attendeurs",
      () async {
    var appels = 0;
    final porte = Completer<void>();

    Future<String?> quiEchoue() async {
      appels++;
      await porte.future;
      throw StateError("refus du serveur");
    }

    final a = VerrouRafraichissement.partage(quiEchoue);
    final b = VerrouRafraichissement.partage(quiEchoue);
    porte.complete();

    await expectLater(a, throwsStateError);
    // 🔴 L'ERREUR DOIT REMONTER, et non être avalée : c'est le code d'erreur du
    // serveur qui dit si la session est fermée. Un verrou qui rendrait `null`
    // en silence priverait l'appelant de la seule information qui compte.
    await expectLater(b, throwsStateError);
    expect(appels, 1);

    // Et la porte n'est pas restée close : l'échec ne condamne pas les suivants.
    expect(await VerrouRafraichissement.partage(() async => "ça repart"),
        "ça repart");
  });
}
