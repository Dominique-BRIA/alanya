// LA RELÈVE DU MOBILE, ÉPROUVÉE SUR LE VRAI CODE — sans APK et sans réseau.
//
// 🔴 CE QUE CE TEST FAIT TOURNER : `CoffreE2ee`, `E2eeService` et `E2eeFil`
// tels qu'ils partent dans l'application, avec la vraie bibliothèque Signal.
// Seuls deux éléments sont simulés : le stockage sécurisé (en mémoire) et le
// serveur (une table d'enveloppes qui suit les routes de `backend-alanya`).
//
// ⚠️ CE QU'IL NE PROUVE PAS : l'écran. Il éprouve le protocole et l'ordre des
// opérations, là où les défauts de relève se cachaient.
//
// Trois défauts, un groupe chacun :
//   ① deux relèves simultanées déchiffraient deux fois le même message ;
//   ② une enveloppe illisible revenait à chaque relève et détruisait la
//     session réparée entre-temps ;
//   ③ le texte devait être rangé AVANT l'acquittement, fil par fil.

import 'package:alanya/services/e2ee/e2ee_coffre.dart';
import 'package:alanya/services/e2ee/e2ee_fil.dart';
import 'package:alanya/services/e2ee/e2ee_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le serveur, réduit aux routes du chiffrement.
class FauxServeur {
  /// compte → appareil → paquet publié.
  final cles = <String, Map<int, Map<String, dynamic>>>{};
  final enveloppes = <Map<String, dynamic>>[];

  /// Les acquittements, dans l'ordre — pour vérifier QUAND ils arrivent.
  final journal = <String>[];
  var _suivant = 0;

  String _id() => 'id${_suivant++}';

  /// L'API telle que la voit UN compte.
  Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?)
      pour(String moi) {
    return (methode, chemin, corps) async {
      // ⚠️ UN VRAI TOUR DE BOUCLE, comme un aller-retour réseau : sans lui,
      // deux relèves lancées ensemble ne s'entrelaceraient jamais.
      await Future<void>.delayed(Duration.zero);
      final uri = Uri.parse(chemin);
      final p = uri.path;

      if (methode == 'PUT' && p == '/api/e2ee/cles') {
        final c = corps!;
        final existant = cles.putIfAbsent(moi, () => {})[c['deviceId'] as int];
        final stock = <Map<String, dynamic>>[
          ...?(existant?['prekeys'] as List<Map<String, dynamic>>?),
          ...(c['prekeys'] as List).cast<Map<String, dynamic>>(),
        ];
        cles[moi]![c['deviceId'] as int] = {...c, 'prekeys': stock};
        return {'prekeysRestantes': stock.length};
      }
      if (methode == 'GET' && p == '/api/e2ee/cles') {
        return {
          'appareils': [
            for (final e in (cles[moi] ?? {}).entries)
              {
                'deviceId': e.key,
                'reapproNecessaire': (e.value['prekeys'] as List).length < 10,
              },
          ],
        };
      }
      if (methode == 'GET' && p.startsWith('/api/e2ee/cles/')) {
        final pair = p.substring('/api/e2ee/cles/'.length);
        return {
          'paquets': [
            for (final e in (cles[pair] ?? {}).entries)
              () {
                final stock = e.value['prekeys'] as List<Map<String, dynamic>>;
                final unique = stock.isEmpty ? null : stock.removeAt(0);
                final s = e.value['prekeySignee'] as Map<String, dynamic>;
                return {
                  'deviceId': e.key,
                  'registrationId': e.value['registrationId'],
                  'cleIdentite': e.value['cleIdentite'],
                  'prekeySignee': {
                    'prekeyId': s['id'],
                    'clePublique': s['clePublique'],
                    'signature': s['signature'],
                  },
                  'prekeyUnique': unique == null
                      ? null
                      : {'prekeyId': unique['id'], 'clePublique': unique['clePublique']},
                };
              }(),
          ],
        };
      }
      if (methode == 'POST' && p.endsWith('/messages')) {
        return {'id': _id(), 'createdAt': DateTime.now().toIso8601String()};
      }
      if (methode == 'POST' && p == '/api/e2ee/enveloppes') {
        for (final e in (corps!['enveloppes'] as List).cast<Map<String, dynamic>>()) {
          depose(
            convId: corps['convId'] as String,
            expediteurId: moi,
            expediteurDevice: corps['deviceId'] as int,
            destinataireId: e['destinataireId'] as String,
            destinataireDevice: e['destinataireDevice'] as int,
            type: e['type'] as int,
            corps: e['corps'] as String,
            messageId: corps['messageId'] as String?,
          );
        }
        return {'deposees': 1};
      }
      if (methode == 'GET' && p == '/api/e2ee/enveloppes') {
        final device = int.parse(uri.queryParameters['deviceId']!);
        return {
          'enveloppes': [
            for (final e in enveloppes)
              if (e['destinataireId'] == moi &&
                  e['destinataireDevice'] == device &&
                  e['remis'] != true)
                Map<String, dynamic>.of(e),
          ],
        };
      }
      if (methode == 'DELETE' && p == '/api/e2ee/enveloppes') {
        final ids = uri.queryParameters['ids']!.split(',');
        for (final e in enveloppes) {
          if (ids.contains(e['id']) && e['destinataireId'] == moi) e['remis'] = true;
        }
        journal.add('acquitte:${ids.join(",")}');
        return {'acquittees': ids.length};
      }
      throw StateError('Route inconnue du faux serveur : $methode $chemin');
    };
  }

  void depose({
    required String convId,
    required String expediteurId,
    required int expediteurDevice,
    required String destinataireId,
    required int destinataireDevice,
    required int type,
    required String corps,
    String? messageId,
  }) {
    enveloppes.add({
      'id': _id(),
      'convId': convId,
      'expediteurId': expediteurId,
      'expediteurDevice': expediteurDevice,
      'destinataireId': destinataireId,
      'destinataireDevice': destinataireDevice,
      'type': type,
      'corps': corps,
      'messageId': messageId ?? _id(),
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  int enAttentePour(String compte) => enveloppes
      .where((e) => e['destinataireId'] == compte && e['remis'] != true)
      .length;
}

/// Un client complet : coffre, service et fil, comme dans `PileE2ee.pour`.
class Client {
  Client(this.compte, FauxServeur serveur)
      : coffre = CoffreE2ee(compte) {
    final api = serveur.pour(compte);
    service = E2eeService(coffre, api);
    fil = E2eeFil(service, api, coffre.deviceId);
  }

  final String compte;
  final CoffreE2ee coffre;
  late final E2eeService service;
  late final E2eeFil fil;

  Future<void> demarrer() async {
    await coffre.preparer();
    await service.publierMesCles(deviceId: await coffre.deviceId());
  }
}

void main() {
  late FauxServeur serveur;
  late Client alice;
  late Client bob;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    serveur = FauxServeur();
    alice = Client('alice', serveur);
    bob = Client('bob', serveur);
    await alice.demarrer();
    await bob.demarrer();
  });

  group('① deux relèves lancées ensemble', () {
    test('ne déchiffrent pas deux fois le même message', () async {
      await alice.fil.envoyer(convId: 'fil-ab', pairId: 'bob', texte: 'un');

      // L'ouverture du fil et la sonnette `e2ee_arrivee`, presque ensemble.
      final r = await Future.wait([bob.fil.relever(), bob.fil.relever()]);

      final lus = [for (final x in r) ...x.messages.map((m) => m.texte)];
      expect(lus, ['un'], reason: 'le message doit être lu UNE fois');
      expect(r.fold<int>(0, (n, x) => n + x.illisibles), 0,
          reason: 'la seconde relève a pris le message déjà ouvert pour un illisible');
    });

    test('et la session survit : le message suivant se lit', () async {
      await alice.fil.envoyer(convId: 'fil-ab', pairId: 'bob', texte: 'un');
      await Future.wait([bob.fil.relever(), bob.fil.relever()]);

      await alice.fil.envoyer(convId: 'fil-ab', pairId: 'bob', texte: 'deux');
      final r = await bob.fil.relever();

      expect(r.messages.map((m) => m.texte), ['deux'],
          reason: 'la relève concurrente a effacé la session de Bob');
      expect(r.illisibles, 0);
    });
  });

  group('② une enveloppe illisible', () {
    test('est acquittée, et ne revient pas détruire la session réparée', () async {
      await alice.fil.envoyer(convId: 'fil-ab', pairId: 'bob', texte: 'un');
      expect((await bob.fil.relever()).messages.single.texte, 'un');

      // Une enveloppe que rien ne peut ouvrir, venue de l'appareil d'Alice.
      serveur.depose(
        convId: 'fil-ab',
        expediteurId: 'alice',
        expediteurDevice: await alice.coffre.deviceId(),
        destinataireId: 'bob',
        destinataireDevice: await bob.coffre.deviceId(),
        type: 1,
        corps: 'AAAA',
      );
      expect((await bob.fil.relever()).illisibles, 1);
      expect(serveur.enAttentePour('bob'), 0,
          reason: "l'illisible reste en tête de file et sera retentée à chaque relève");

      // La réparation prévue : Bob écrit, Alice adopte la nouvelle session.
      await bob.fil.envoyer(convId: 'fil-ab', pairId: 'alice', texte: 'réparons');
      expect((await alice.fil.relever()).messages.single.texte, 'réparons');

      await alice.fil.envoyer(convId: 'fil-ab', pairId: 'bob', texte: 'trois');
      final r = await bob.fil.relever();
      expect(r.messages.map((m) => m.texte), ['trois'],
          reason: "l'illisible, relue, a de nouveau effacé la session réparée");
      expect(r.illisibles, 0);
    });
  });

  group('③ le rangement', () {
    test('reçoit les messages de TOUS les fils, avant tout acquittement', () async {
      final carole = Client('carole', serveur);
      await carole.demarrer();

      await alice.fil.envoyer(convId: 'fil-ab', pairId: 'bob', texte: 'Alice');
      await carole.fil.envoyer(convId: 'fil-cb', pairId: 'bob', texte: 'Carole');

      final ranges = <String, String>{};
      var acquittementsAuRangement = -1;
      await bob.fil.relever(ranger: (messages) async {
        acquittementsAuRangement = serveur.journal.length;
        for (final m in messages) {
          ranges[m.convId] = m.texte;
        }
      });

      expect(ranges, {'fil-ab': 'Alice', 'fil-cb': 'Carole'});
      expect(acquittementsAuRangement, 0,
          reason: 'le rangement doit passer AVANT l’acquittement');
      expect(serveur.enAttentePour('bob'), 0);
    });
  });
}
