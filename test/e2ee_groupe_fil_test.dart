// LE GROUPE CHIFFRÉ DU MOBILE, ÉPROUVÉ SUR LE VRAI CODE — lot 3, chapitre 34.
//
// 🔴 CE QUE CE TEST FAIT TOURNER : `CoffreE2ee`, `E2eeService`, `E2eeFil` et
// `GroupeChiffre` tels qu'ils partent dans l'application, avec la vraie
// bibliothèque Signal. Le serveur est le faux de `e2ee_releve_test.dart`,
// étendu aux routes du groupe (lot 2 de `backend-alanya`).
//
//   ① le trousseau arrive hors fil, d'un administrateur, et se range ;
//   ② un message part en UN chiffré, et chaque membre le relit ;
//   ③ un membre jamais rencontré : la session s'ouvre pour vérifier sa signature ;
//   ④ la modification remplace le chiffré ;
//   ⑤ les refus : trousseau d'un non-administrateur, clé connue remplacée,
//     chiffré altéré, version périmée (rien ne part) ;
//   ⑥ l'oubli au départ ;
//   ⑦ un FICHIER : sa clé voyage dans le chiffré de groupe, chaque membre
//     l'ouvre, le serveur ne la voit jamais, un fichier altéré est refusé.

import 'dart:convert';
import 'dart:typed_data';

import 'package:alanya/core/api_client.dart' show ApiException;
import 'package:alanya/services/e2ee/e2ee_groupe.dart' as g;
import 'package:alanya/services/e2ee/e2ee_groupe_fil.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2ee_releve_test.dart' show FauxServeur, Client;

/// Le faux serveur, avec les routes du groupe.
class FauxServeurGroupe extends FauxServeur {
  FauxServeurGroupe(this.membres);

  /// compte → rôle.
  final Map<String, String> membres;
  var cleVersion = 1;
  final messages = <String, Map<String, dynamic>>{};

  /// ⚠️ Une enveloppe HORS FIL garde `messageId` nul — c'est ainsi que voyage
  /// le trousseau. Le faux d'origine en inventait un.
  @override
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
    super.depose(
      convId: convId,
      expediteurId: expediteurId,
      expediteurDevice: expediteurDevice,
      destinataireId: destinataireId,
      destinataireDevice: destinataireDevice,
      type: type,
      corps: corps,
      messageId: messageId,
    );
    if (messageId == null) enveloppes.last['messageId'] = null;
  }

  @override
  Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?) pour(
      String moi) {
    final base = super.pour(moi);
    return (methode, chemin, corps) async {
      final p = Uri.parse(chemin).path;
      if (p == '/api/conversations/g1/members' && methode == 'GET') {
        return {
          'members': [
            for (final e in membres.entries) {'id': e.key, 'role': e.value},
          ],
        };
      }
      if (p == '/api/conversations/g1/messages' && methode == 'POST' && corps?['groupe'] != null) {
        final gr = corps!['groupe'] as Map<String, dynamic>;
        if (gr['version'] != cleVersion) {
          throw ApiException(409, 'La clé du groupe a changé', 'VERSION_PERIMEE');
        }
        final id = corps['id'] as String;
        messages[id] = {
          'id': id,
          'senderId': moi,
          // Tout ce que le serveur a reçu, pour prouver ce qu'il n'a PAS vu.
          'recu': jsonEncode(corps),
          'groupe': {
            'version': gr['version'],
            'expediteurAppareil': gr['appareil'],
            'corps': gr['corps'],
          },
        };
        return {'id': id, 'createdAt': DateTime.now().toIso8601String()};
      }
      if (p.startsWith('/api/conversations/g1/messages/') && methode == 'PATCH') {
        final gr = corps!['groupe'] as Map<String, dynamic>;
        if (gr['version'] != cleVersion) {
          throw ApiException(409, 'La clé du groupe a changé', 'VERSION_PERIMEE');
        }
        final id = p.split('/').last;
        messages[id]!['groupe'] = {
          'version': gr['version'],
          'expediteurAppareil': gr['appareil'],
          'corps': gr['corps'],
        };
        return {'id': id, 'editedAt': DateTime.now().toIso8601String()};
      }
      return base(methode, chemin, corps);
    };
  }
}

/// Envoie un trousseau hors fil, de [de] à [pour], par les vraies sessions.
Future<void> distribuer(Client de, FauxServeurGroupe serveur, List<Client> pour,
    List<g.VersionCle> versions) async {
  final charge = g.ecrireChargeTrousseau(
      g.Trousseau(convId: 'g1', motif: 'ACTIVATION', versions: versions));
  final api = serveur.pour(de.compte);
  final enveloppes = <Map<String, dynamic>>[];
  for (final c in pour) {
    for (final d in await de.service.ouvrirSessions(c.compte)) {
      final e = await de.service.chiffrer(c.compte, d, charge);
      enveloppes.add({
        'destinataireId': c.compte,
        'destinataireDevice': d,
        'type': e.type,
        'corps': e.corps,
      });
    }
  }
  await api('POST', '/api/e2ee/enveloppes', {
    'convId': 'g1',
    'deviceId': await de.coffre.deviceId(),
    'enveloppes': enveloppes,
  });
}

g.VersionCle version(int n, [int graine = 1]) => g.VersionCle(
    n: n, cle: Uint8List.fromList(List.generate(32, (i) => (i * graine + n) % 256)), creeLe: 1);

void main() {
  late FauxServeurGroupe serveur;
  late Client alice;
  late Client bob;
  late Client carole;

  Future<(ClairGroupe?, EchecGroupe?)> lirePar(Client qui, String id) {
    final m = serveur.messages[id]!;
    return qui.fil.groupe.lire(
      convId: 'g1',
      messageId: id,
      expediteurId: m['senderId'] as String,
      chiffre: m['groupe'] as Map<String, dynamic>,
    );
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    serveur = FauxServeurGroupe({'alice': 'ADMIN', 'bob': 'MEMBER', 'carole': 'MEMBER'});
    alice = Client('alice', serveur);
    bob = Client('bob', serveur);
    carole = Client('carole', serveur);
    await alice.demarrer();
    await bob.demarrer();
    await carole.demarrer();
    await alice.fil.groupe.ranger('g1', [version(1)]);
    await distribuer(alice, serveur, [bob, carole], [version(1)]);
    await bob.fil.relever();
    await carole.fil.relever();
  });

  test('① le trousseau de l’administratrice arrive et se range', () async {
    expect((await bob.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
    expect((await carole.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
    expect(base64.encode((await bob.fil.groupe.trousseau('g1')).single.cle),
        base64.encode(version(1).cle));
  });

  test('② un seul chiffré, relu par chaque membre (et par l’expéditrice)', () async {
    final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'Bonjour le groupe');
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id),
        isTrue, reason: 'identifiant tiré par l’appareil : UUID v4');
    expect(serveur.enveloppes.where((e) => e['messageId'] == id), isEmpty,
        reason: 'aucune enveloppe pour un message de groupe');
    for (final qui in [bob, carole, alice]) {
      final (clair, echec) = await lirePar(qui, id);
      expect(echec, isNull, reason: qui.compte);
      expect(clair!.texte, 'Bonjour le groupe');
    }
  });

  test('③ un membre jamais rencontré : sa signature se vérifie après ouverture de session',
      () async {
    // Bob n'a jamais échangé avec Carole : aucune identité connue.
    final id = await carole.fil.envoyer(convId: 'g1', pairId: null, texte: 'Je suis Carole');
    final (clair, echec) = await lirePar(bob, id);
    expect(echec, isNull);
    expect(clair!.texte, 'Je suis Carole');
  });

  test('④ la modification remplace le chiffré', () async {
    final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'avant');
    await alice.fil.modifier(convId: 'g1', pairId: null, messageId: id, texte: 'après');
    final (clair, _) = await lirePar(bob, id);
    expect(clair!.texte, 'après');
    expect(clair.modifie, isTrue);
  });

  group('⑤ les refus', () {
    test('trousseau envoyé par un non-administrateur : ignoré', () async {
      await distribuer(carole, serveur, [bob], [version(2)]);
      await bob.fil.relever();
      expect((await bob.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
      // Témoin : la MÊME version, envoyée par l'administratrice, est acceptée.
      await distribuer(alice, serveur, [bob], [version(2)]);
      await bob.fil.relever();
      expect((await bob.fil.groupe.trousseau('g1')).map((v) => v.n), [1, 2]);
    });

    test('version connue avec une autre clé : refusée', () async {
      await distribuer(alice, serveur, [bob], [version(1, 7)]);
      await bob.fil.relever();
      expect(base64.encode((await bob.fil.groupe.trousseau('g1')).single.cle),
          base64.encode(version(1).cle));
    });

    test('chiffré altéré : refusé, rien d’affiché', () async {
      final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'secret');
      final gr = serveur.messages[id]!['groupe'] as Map<String, dynamic>;
      final octets = base64.decode(gr['corps'] as String);
      octets[20] ^= 0xff;
      gr['corps'] = base64.encode(octets);
      final (clair, echec) = await lirePar(bob, id);
      expect(clair, isNull);
      expect(echec, EchecGroupe.invalide);
    });

    test('attribué à un autre membre : refusé', () async {
      final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'de moi');
      serveur.messages[id]!['senderId'] = 'carole';
      final (clair, echec) = await lirePar(bob, id);
      expect(clair, isNull);
      expect(echec, isNot(isNull));
    });

    test('la clé a changé et le trousseau manque : rien ne part', () async {
      serveur.cleVersion = 2;
      final avant = serveur.messages.length;
      await expectLater(
          alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'non'), throwsA(isA<CleGroupeAbsente>()));
      expect(serveur.messages.length, avant);
    });
  });

  test('⑥ au départ, la clé est oubliée', () async {
    final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'avant le départ');
    await carole.fil.groupe.oublier('g1');
    expect(await carole.fil.groupe.trousseau('g1'), isEmpty);
    final (clair, echec) = await lirePar(carole, id);
    expect(clair, isNull);
    expect(echec, EchecGroupe.cleAbsente);
  });

  group('⑦ un fichier dans le groupe', () {
    // Une « photo » de 200 Ko : plusieurs blocs de chiffrement.
    final photo = Uint8List.fromList(List<int>.generate(200 * 1024, (i) => (i * 31 + 7) % 256));

    Future<(String, FichierChiffre)> envoyerPhoto() async {
      final f = chiffrerFichier(photo);
      final d = DescripteurMedia(
        id: 'media-1',
        cle: f.cle,
        empreinte: f.empreinte,
        taille: photo.length,
        mime: 'image/jpeg',
        nom: 'plage.jpg',
        largeur: 800,
        hauteur: 600,
      );
      final id = await alice.fil.envoyerMedia(
          convId: 'g1', pairId: null, media: d, legende: 'La plage');
      return (id, f);
    }

    test('chaque membre reçoit la clé dans le chiffré, et ouvre le fichier', () async {
      final (id, f) = await envoyerPhoto();
      for (final qui in [bob, carole, alice]) {
        final (clair, echec) = await lirePar(qui, id);
        expect(echec, isNull, reason: qui.compte);
        expect(clair!.texte, 'La plage');
        final d = clair.media!;
        expect((d.id, d.mime, d.nom, d.largeur, d.hauteur),
            ('media-1', 'image/jpeg', 'plage.jpg', 800, 600));
        final ouvert =
            dechiffrerFichier(f.chiffre, cle: d.cle, empreinte: d.empreinte, taille: d.taille);
        expect(ouvert, photo, reason: '${qui.compte} retrouve le fichier, octet pour octet');
      }
    });

    test('le serveur ne reçoit ni la clé, ni l’empreinte, ni le nom du fichier', () async {
      final (id, f) = await envoyerPhoto();
      final recu = serveur.messages[id]!['recu'] as String;
      expect(recu.contains(f.cle), isFalse, reason: 'la clé du fichier');
      expect(recu.contains(f.empreinte), isFalse, reason: 'l’empreinte');
      expect(recu.contains('plage.jpg'), isFalse, reason: 'le nom');
      expect(recu.contains('La plage'), isFalse, reason: 'la légende');
      final corps = jsonDecode(recu) as Map<String, dynamic>;
      expect(corps['mediaIds'], ['media-1'], reason: 'seul l’identifiant du fichier est en clair');
      expect(corps['type'], 'IMAGE');
    });

    test('un fichier remplacé ou abîmé sur le serveur est refusé', () async {
      final (id, f) = await envoyerPhoto();
      final (clair, _) = await lirePar(bob, id);
      final d = clair!.media!;
      final abime = Uint8List.fromList(f.chiffre)..[1000] ^= 0x01;
      expect(() => dechiffrerFichier(abime, cle: d.cle, empreinte: d.empreinte, taille: d.taille),
          throwsA(isA<FichierInvalide>()));
    });

    test('un ancien membre, sans la clé du groupe, n’obtient pas celle du fichier', () async {
      await carole.fil.groupe.oublier('g1');
      final (id, _) = await envoyerPhoto();
      final (clair, echec) = await lirePar(carole, id);
      expect(clair, isNull);
      expect(echec, EchecGroupe.cleAbsente);
    });
  });

  test('administrateur : même règle que le serveur, repli « premier arrivé »', () {
    expect(estAdministrateur([
      {'id': 'a', 'role': 'MEMBER', 'joinedAt': '2026-01-02'},
      {'id': 'b', 'role': 'ADMIN', 'joinedAt': '2026-01-03'},
    ], 'b'), isTrue);
    expect(estAdministrateur([
      {'id': 'a', 'role': 'MEMBER', 'joinedAt': '2026-01-02'},
      {'id': 'b', 'role': 'MEMBER', 'joinedAt': '2026-01-01'},
    ], 'b'), isTrue);
    expect(estAdministrateur([
      {'id': 'a', 'role': 'MEMBER', 'joinedAt': '2026-01-02'},
      {'id': 'b', 'role': 'MEMBER', 'joinedAt': '2026-01-01'},
    ], 'a'), isFalse);
  });
}
