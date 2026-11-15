import 'dart:convert';

// LE RENVOI PAR L'EXPÉDITEUR (piste B), ÉPROUVÉ SUR LE VRAI CODE.
//
// `RenvoisE2ee`, `E2eeService` et `E2eeFil` tels qu'ils partent dans
// l'application, avec la vraie bibliothèque Signal. Seuls le stockage
// sécurisé (en mémoire) et le serveur sont simulés ; le faux serveur des
// relèves (`e2ee_releve_test.dart`) reçoit ici les trois routes de
// `api/e2ee/renvois`, avec les mêmes règles que le vrai.
//
// Le scénario : Bob n'a qu'un téléphone. Alice lui écrit pendant qu'il est
// éteint, puis le téléphone disparaît. Bob se connecte sur un NOUVEL appareil.

import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:alanya/services/e2ee/e2ee_renvois.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2ee_releve_test.dart' show Client, FauxServeur;

/// Le faux serveur, avec les demandes de renvoi.
class ServeurRenvois extends FauxServeur {
  final demandes = <Map<String, dynamic>>[];
  var _n = 0;

  @override
  Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?) pour(
      String moi) {
    final base = super.pour(moi);
    return (methode, chemin, corps) async {
      await Future<void>.delayed(Duration.zero);
      if (methode == 'POST' && chemin == '/api/e2ee/renvois') {
        final device = corps!['deviceId'] as int;
        // Mêmes règles que la route réelle : chiffré pour moi par un autre,
        // relevé par AUCUN de mes appareils, jamais reçu par celui-ci.
        final parMessage = <String, List<Map<String, dynamic>>>{};
        for (final e in enveloppes) {
          if (e['destinataireId'] == moi && e['expediteurId'] != moi) {
            parMessage.putIfAbsent(e['messageId'] as String, () => []).add(e);
          }
        }
        var crees = 0;
        parMessage.forEach((messageId, liste) {
          final releve = liste.any((e) => e['remis'] == true);
          final dejaIci = liste.any((e) => e['destinataireDevice'] == device);
          final doublon = demandes.any((d) =>
              d['messageId'] == messageId &&
              d['demandeurId'] == moi &&
              d['demandeurDevice'] == device);
          if (releve || dejaIci || doublon) return;
          demandes.add({
            'id': 'r${_n++}',
            'messageId': messageId,
            'convId': liste.first['convId'],
            'expediteurId': liste.first['expediteurId'],
            'demandeurId': moi,
            'demandeurDevice': device,
            'servi': false,
          });
          crees++;
        });
        return {'demandes': crees};
      }
      if (methode == 'GET' && chemin == '/api/e2ee/renvois') {
        return {
          'demandes': [
            for (final d in demandes)
              if (d['expediteurId'] == moi && d['servi'] != true) Map<String, dynamic>.of(d),
          ],
        };
      }
      if (methode == 'POST' && chemin == '/api/e2ee/renvois/servir') {
        final d = demandes.firstWhere((x) => x['id'] == corps!['id']);
        if (d['expediteurId'] != moi) throw StateError('demande d’un autre');
        if (d['servi'] == true) return {'deja': true};
        d['servi'] = true;
        depose(
          convId: d['convId'] as String,
          expediteurId: moi,
          expediteurDevice: corps!['deviceId'] as int,
          destinataireId: d['demandeurId'] as String,
          destinataireDevice: d['demandeurDevice'] as int,
          type: corps['type'] as int,
          corps: corps['corps'] as String,
          messageId: d['messageId'] as String,
        );
        return {'servi': true};
      }
      return base(methode, chemin, corps);
    };
  }
}

void main() {
  late ServeurRenvois serveur;
  late Client alice;
  late Client bobAncien;

  /// Ce que le cache d'Alice garde de SES messages.
  late Map<String, ClairARenvoyer> cacheAlice;

  RenvoisE2ee renvoisDe(Client c, Map<String, ClairARenvoyer> Function() cache) =>
      RenvoisE2ee(
        api: serveur.pour(c.compte),
        service: c.service,
        monAppareil: c.coffre.deviceId,
        lireClairs: (_) async => cache(),
      );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    serveur = ServeurRenvois();
    alice = Client('alice', serveur);
    bobAncien = Client('bob', serveur, stockage: 'bob-ancien');
    await alice.demarrer();
    await bobAncien.demarrer();
    cacheAlice = {};
  });

  /// Alice écrit à Bob, qui n'a encore que son ancien téléphone, éteint.
  Future<String> aliceEcrit(String texte, {String? reponseA}) async {
    final id = await alice.fil.envoyer(
        convId: 'fil-ab', pairId: 'bob', texte: texte, replyToId: reponseA);
    cacheAlice[id] = ClairARenvoyer(texte: texte, reponseA: reponseA);
    return id;
  }

  /// Le nouvel appareil de Bob, publié APRÈS les messages.
  Future<Client> nouvelAppareilDeBob() async {
    final c = Client('bob', serveur, stockage: 'bob-neuf');
    await c.demarrer();
    return c;
  }

  test('le message perdu revient sur le nouvel appareil, lisible', () async {
    final id = await aliceEcrit('bonjour');
    final bob = await nouvelAppareilDeBob();
    // Sans renvoi, rien n'attend le nouvel appareil.
    expect((await bob.fil.relever()).messages, isEmpty);

    expect(await renvoisDe(bob, () => {}).demander(), 1);
    expect(await renvoisDe(alice, () => cacheAlice).servir(), 1);

    final r = await bob.fil.relever();
    expect(r.illisibles, 0);
    expect(r.messages.single.texte, 'bonjour');
    expect(r.messages.single.id, id, reason: 'la bulle existante doit se remplir');
    expect(r.messages.single.expediteurId, 'alice');
  });

  test('la réponse citée voyage avec le renvoi', () async {
    final premier = await aliceEcrit('question');
    await aliceEcrit('réponse', reponseA: premier);
    final bob = await nouvelAppareilDeBob();

    await renvoisDe(bob, () => {}).demander();
    expect(await renvoisDe(alice, () => cacheAlice).servir(), 2);

    final r = await bob.fil.relever();
    final reponse = r.messages.firstWhere((m) => m.texte == 'réponse');
    expect(reponse.reponseA, premier);
  });

  test('un média chiffré est renvoyé avec sa clé', () async {
    // Une clé AES-256 et une empreinte SHA-256 de la bonne taille : la
    // lecture de la charge refuse un descripteur mal formé.
    final media = DescripteurMedia(
        id: 'media-1',
        cle: base64Encode(List.filled(32, 7)),
        empreinte: base64Encode(List.filled(32, 9)),
        taille: 12,
        mime: 'image/jpeg');
    final id = await alice.fil.envoyerMedia(
        convId: 'fil-ab', pairId: 'bob', media: media, legende: 'photo');
    cacheAlice[id] = ClairARenvoyer(texte: 'photo', media: media);
    final bob = await nouvelAppareilDeBob();

    await renvoisDe(bob, () => {}).demander();
    await renvoisDe(alice, () => cacheAlice).servir();

    final m = (await bob.fil.relever()).messages.single;
    expect(m.media?.id, 'media-1');
    expect(m.media?.cle, media.cle);
  });

  test('un message déjà relevé par un autre appareil n’est pas redemandé', () async {
    await aliceEcrit('vu');
    expect((await bobAncien.fil.relever()).messages.single.texte, 'vu');
    final bob = await nouvelAppareilDeBob();

    expect(await renvoisDe(bob, () => {}).demander(), 0);
  });

  test('une demande ne se sert qu’une fois, et ne se recrée pas', () async {
    await aliceEcrit('une fois');
    final bob = await nouvelAppareilDeBob();
    final renvoisBob = renvoisDe(bob, () => {});

    expect(await renvoisBob.demander(), 1);
    expect(await renvoisBob.demander(), 0, reason: 'demande en double');
    expect(await renvoisDe(alice, () => cacheAlice).servir(), 1);
    expect(await renvoisDe(alice, () => cacheAlice).servir(), 0);
    expect((await bob.fil.relever()).messages.map((m) => m.texte), ['une fois']);
  });

  test('sans le clair dans son cache, l’expéditeur ne sert rien et la demande attend', () async {
    await aliceEcrit('oublié');
    final bob = await nouvelAppareilDeBob();
    await renvoisDe(bob, () => {}).demander();

    expect(await renvoisDe(alice, () => {}).servir(), 0);
    expect(serveur.demandes.single['servi'], isFalse,
        reason: 'un autre appareil d’Alice pourra encore la servir');
  });

  test('ma propre copie n’est jamais demandée', () async {
    await aliceEcrit('à Bob');
    // Un second appareil d'Alice, apparu après l'envoi.
    final alice2 = Client('alice', serveur, stockage: 'alice-2');
    await alice2.demarrer();
    expect(await renvoisDe(alice2, () => {}).demander(), 0);
  });

  test('la session continue après le renvoi : le message suivant se lit', () async {
    await aliceEcrit('perdu');
    final bob = await nouvelAppareilDeBob();
    await renvoisDe(bob, () => {}).demander();
    await renvoisDe(alice, () => cacheAlice).servir();
    expect((await bob.fil.relever()).messages.single.texte, 'perdu');

    await aliceEcrit('suivant');
    final r = await bob.fil.relever();
    expect(r.illisibles, 0);
    expect(r.messages.single.texte, 'suivant');
  });

  test('un serveur sans la route ne fait rien lever', () async {
    final r = RenvoisE2ee(
      api: (m, c, b) async => throw StateError('404'),
      service: alice.service,
      monAppareil: alice.coffre.deviceId,
      lireClairs: (_) async => {},
    );
    expect(await r.demander(), 0);
    expect(await r.servir(), 0);
  });
}
