import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/ouverture_conversation.dart';
import 'package:alanya/models/message.dart';

/// Spécification exécutable d'UNE règle : **le fil connu passe avant
/// l'attente, et une panne se dit — elle ne tourne pas.**
///
/// 🔴 POURQUOI CE FICHIER. Défaut signalé le 26/09/2026 : « lorsque j'ouvre une
/// conversation, le chargement est infini ». L'écran enchaînait trois attentes —
/// la base locale, le jeton du coffre sécurisé, le serveur — et aucune ne
/// pouvait faire échouer l'affichage : la roue continuait de tourner, y compris
/// quand le cache local connaissait déjà chaque message du fil.
///
/// La correction ne tenait pas sans contrôles. Ce qui la fixe, c'est la
/// DISTINCTION qu'aucun `if` de l'écran ne faisait : un fil que le serveur
/// annonce vide est vide, un fil que le serveur ne rend pas est EN PANNE. Le
/// premier se dit « aucun message », le second se dit « réessayez ». Confondre
/// les deux donnait soit un mensonge, soit une roue sans fin.
///
/// ⚠️ CES CONTRÔLES PORTENT SUR LA RÈGLE, PAS SUR L'ÉCRAN. `_load()` ne se
/// teste pas : ses dépendances sont adossées aux canaux de plateforme
/// (`flutter_secure_storage`, `sqflite`) et à un arbre de widgets. Même raison
/// que `session_expiration_test.dart` — la décision est sortie en fonction pure,
/// c'est le seul niveau où elle est vraie une fois pour toutes.
///
/// Lancer avec : flutter test test/ouverture_conversation_test.dart
void main() {
  Message un(String id) => Message(
        id: id,
        convId: "conv-1",
        senderId: "u-1",
        content: id,
        type: "TEXT",
        status: "SENT",
        replyToId: null,
        media: const [],
        createdAt: DateTime.utc(2026, 9, 26),
      );

  group("Le serveur n'a RIEN rendu — le cache a tous les droits", () {
    test("le fil connu est rendu tel quel, et le cache n'y touche pas", () {
      final caches = [un("m1"), un("m2")];

      final issue = decideOuverture(caches: caches, recus: null);

      expect(issue.messages, same(caches),
          reason: "on rend CE qui est en cache, pas une copie recomposée");
      expect(issue.cacheAReecrire, isFalse,
          reason: "🔴 Écrire un cache depuis une PANNE effacerait l'historique "
              "connu pour une simple coupure réseau : `putConv` commence par "
              "supprimer la conversation entière");
      expect(issue.enPanne, isFalse,
          reason: "l'utilisateur a son fil sous les yeux — c'est déjà tout ce "
              "qu'il demandait. Le bandeau « hors ligne » global le dit, une "
              "seconde alerte ici ne ferait que crier");
    });

    test("rien en cache non plus : c'est une panne à dire, pas une roue", () {
      final issue = decideOuverture(caches: const [], recus: null);

      expect(issue.messages, isEmpty);
      expect(issue.enPanne, isTrue,
          reason: "LE CAS DU RAPPORT : ni cache, ni réseau. Avant, la roue. "
              "Maintenant, un écran qui dit l'échec et propose de reprendre");
      expect(issue.cacheAReecrire, isFalse,
          reason: "surtout pas : on n'écrit pas un vide dans le cache parce "
              "que le serveur n'a pas répondu");
    });
  });

  group("Le serveur a répondu — lui seul prime", () {
    test("sa page VIDE est une réponse, et le cache la suit", () {
      final caches = [un("m1"), un("m2")];

      final issue = decideOuverture(caches: caches, recus: const []);

      expect(issue.messages, isEmpty);
      expect(issue.cacheAReecrire, isTrue,
          reason: "⚠️ LE CONTRÔLE QUI EN VAUT UN AUTRE : un fil que le serveur "
              "annonce vide est vide — c'est par là qu'une « suppression pour "
              "tous » atteint l'appareil. Garder le cache par peur du vide "
              "laisserait relire, à chaque ouverture, des messages effacés");
      expect(issue.enPanne, isFalse);
    });

    test("ses messages passent, le cache est réécrit", () {
      final recus = [un("m3")];

      final issue = decideOuverture(caches: [un("m1")], recus: recus);

      expect(issue.messages, same(recus));
      expect(issue.cacheAReecrire, isTrue);
      expect(issue.enPanne, isFalse);
    });

    test("`null` et liste vide ne sont PAS la même chose", () {
      // LA DISTINCTION SUR LAQUELLE TOUT TIENT, et qu'aucun type ne force :
      // les deux sont « rien à afficher » pour un `List`. C'est `null` qui veut
      // dire « rien de reçu », et seul le type le sait.
      final panne = decideOuverture(caches: const [], recus: null);
      final vide = decideOuverture(caches: const [], recus: const []);

      expect(panne.enPanne, isTrue);
      expect(vide.enPanne, isFalse);
      expect(panne.cacheAReecrire, isFalse);
      expect(vide.cacheAReecrire, isTrue);
    });
  });
}
