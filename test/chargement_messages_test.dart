import 'dart:io';

import 'package:alanya/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// « Quand j'ouvre une conversation, ça charge indéfiniment. »
///
/// 🔴 CE TEST EXISTE POUR QUE CE SYMPTÔME NE PUISSE PAS REVENIR SANS ÊTRE VU.
/// Il ne vérifie pas une fonctionnalité : il vérifie une PROPRIÉTÉ — l'écran de
/// conversation ne doit jamais attendre sans borne, et jamais hors
/// surveillance. C'est exactement ce qui manquait.
///
/// ⚠️ POURQUOI ON LIT LES SOURCES. `_load()` et `_echecDeChargement()` sont
/// privés à l'état de l'écran, et monter l'écran entier demanderait six
/// fournisseurs, un serveur, une base SQLite et un WebSocket pour éprouver une
/// question qui est de forme : « y a-t-il un `await` avant le `try` ? ». Le
/// dépôt procède déjà ainsi pour la parité des langues
/// (`test/l10n_parite_test.dart`), et pour la même raison.
void main() {
  test("le chargement du fil n'attend RIEN avant sa surveillance", () {
    final fichier = File("lib/features/chat/screens/chat_screen.dart");
    expect(fichier.existsSync(), isTrue,
        reason: "le test doit tourner depuis la racine du paquet");
    final src = fichier.readAsStringSync();

    final debut = src.indexOf('Future<void> _load() async {');
    expect(debut, greaterThanOrEqualTo(0), reason: "`_load()` introuvable");

    final corps = src.substring(debut);
    final tryIdx = corps.indexOf('try {');
    expect(tryIdx, greaterThan(0), reason: "`_load()` n'a plus de `try`");

    // Les commentaires peuvent parler d'`await` sans en être : on les retire
    // avant de conclure, sinon le test interdit de documenter le correctif.
    final prologue = corps
        .substring(0, tryIdx)
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') &&
              !t.startsWith('*') &&
              !t.startsWith('/*');
        })
        .join('\n');

    expect(
      prologue.contains('await'),
      isFalse,
      reason: "Un `await` hors du `try` part en exception non capturée : "
          "`_loading` reste alors à `true` pour toujours — un cercle qui "
          "tourne, sans message ni bouton. Tout ce qui attend dans `_load()` "
          "doit être sous surveillance.\n--- prologue fautif ---\n$prologue",
    );
  });

  test("aucune requête JSON de l'API n'est laissée sans borne", () {
    final src = File("lib/core/api_client.dart").readAsStringSync();

    /*
     * Chaque appel doit être le PREMIER argument d'un `_borne(...)`. On regarde
     * en arrière depuis l'appel : c'est là que se voit la différence entre
     * `await http.get(...)` — qui peut ne jamais revenir — et
     * `await _borne(http.get(...), ...)`, qui rend la main au bout de
     * [ApiClient.delaiJson].
     */
    for (final verbe in [
      'http.get(',
      'http.post(',
      'http.patch(',
      'http.put(',
      'http.delete(',
    ]) {
      var i = src.indexOf(verbe);
      expect(i, greaterThanOrEqualTo(0), reason: "$verbe a disparu du client");
      while (i >= 0) {
        final avant = src.substring(i - 120 < 0 ? 0 : i - 120, i);
        expect(avant.contains('_borne('), isTrue,
            reason: "$verbe à l'offset $i n'est pas passé à `_borne()` : "
                "cette requête peut ne jamais aboutir, et ce qui l'attend "
                "avec elle.");
        i = src.indexOf(verbe, i + 1);
      }
    }
  });

  test("une réponse qui ne vient jamais lève, au lieu d'attendre sans fin",
      () async {
    /*
     * LE CAS EXACT DU DÉFAUT : le serveur ACCEPTE la connexion puis se tait.
     * Ni refus (qui échoue vite et proprement), ni réponse : c'est ce silence
     * qui laissait l'écran de conversation tourner indéfiniment.
     */
    final serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((_) {
      // Volontairement AUCUNE réponse, et on ne ferme rien.
    });

    final api = ApiClient(
      baseUrl: "http://127.0.0.1:${serveur.port}",
      delaiReponse: const Duration(milliseconds: 300),
    );

    final montre = Stopwatch()..start();
    await expectLater(
      api.get("/api/conversations/abc/messages"),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 408)
          .having((e) => e.code, 'code', 'DELAI_DEPASSE')),
    );
    montre.stop();

    expect(montre.elapsedMilliseconds, lessThan(5000),
        reason: "l'attente doit être bornée par `delaiReponse`, pas par "
            "l'absence de réponse du serveur");
    // ⚠️ LE DÉFAUT DE L'APPLICATION RESTE 30 s — c'est le test qui raccourcit
    // son propre délai, et rien d'autre.
    expect(ApiClient.delaiJson, const Duration(seconds: 30));

    await serveur.close(force: true);
  });
}
