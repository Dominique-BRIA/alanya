// LOTS 5 ET 6 DU MOBILE — administrer un groupe chiffré, et retrouver ses clés
// sur un nouveau téléphone (cours, chapitre 35).
//
// Vraie bibliothèque Signal, vrai coffre (stockage simulé), faux serveur aux
// routes du lot 2. Et un VECTEUR produit par WebCrypto, comme le navigateur :
// une copie déposée par le web doit s'ouvrir ici, octet pour octet.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/core/api_client.dart' show ApiException;
import 'package:alanya/services/e2ee/e2ee_groupe.dart' show ecrireDemandeTrousseau;
import 'package:alanya/services/e2ee/e2ee_trousseau_perso.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2ee_groupe_fil_test.dart' show FauxServeurGroupe;
import 'e2ee_releve_test.dart' show Client;

/// Le faux serveur du groupe, plus l'activation, les versions et les copies.
class FauxServeurAdmin extends FauxServeurGroupe {
  FauxServeurAdmin(super.membres, this.numeros);

  /// compte → numéro public.
  final Map<String, String> numeros;
  var actif = false;

  /// compte → copie chiffrée.
  final copies = <String, String>{};

  @override
  Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?) pour(
      String moi) {
    final base = super.pour(moi);
    return (methode, chemin, corps) async {
      final p = Uri.parse(chemin).path;
      if (p == '/api/conversations/g1/members' && methode == 'GET') {
        return {
          'members': [
            for (final e in membres.entries)
              {'id': e.key, 'role': e.value, 'publicNumber': numeros[e.key]},
          ],
        };
      }
      if (p == '/api/conversations/g1/e2ee' && methode == 'POST') {
        if (membres[moi] != 'ADMIN') throw ApiException(403, 'admin requis', 'ADMIN_REQUIS');
        if (actif) return {'e2eeActif': true, 'deja': true, 'cleVersion': cleVersion};
        actif = true;
        cleVersion = 1;
        return {'e2eeActif': true, 'deja': false, 'cleVersion': 1};
      }
      if (p == '/api/conversations/g1/e2ee' && methode == 'GET') {
        return {'e2eeActif': actif, 'cleVersion': cleVersion, 'groupe': true};
      }
      if (p == '/api/conversations/g1/e2ee/versions' && methode == 'POST') {
        if (membres[moi] != 'ADMIN') throw ApiException(403, 'admin requis', 'ADMIN_REQUIS');
        if (corps!['attendue'] != cleVersion + 1) {
          throw ApiException(409, 'conflit', 'VERSION_CONFLIT');
        }
        cleVersion = corps['attendue'] as int;
        return {'cleVersion': cleVersion};
      }
      if (p == '/api/e2ee/trousseaux/g1' && methode == 'PUT') {
        copies[moi] = corps!['corps'] as String;
        return {'convId': 'g1'};
      }
      if (p == '/api/e2ee/trousseaux/g1' && methode == 'GET') {
        final c = copies[moi];
        if (c == null) throw ApiException(404, 'aucune copie', 'AUCUNE_COPIE');
        return {'convId': 'g1', 'corps': c};
      }
      if (p == '/api/e2ee/trousseaux' && methode == 'GET') {
        return {
          'trousseaux': [
            if (copies[moi] != null) {'convId': 'g1', 'corps': copies[moi]},
          ],
        };
      }
      return base(methode, chemin, corps);
    };
  }
}

Uint8List maitresseDe(int graine) => Uint8List.fromList(List.generate(32, (i) => (i * 7 + graine) % 256));

Future<void> attendre(bool Function() condition) async {
  for (var i = 0; i < 50 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('la copie personnelle, format commun au web', () {
    final vecteur = jsonDecode(File('test/donnees/vecteur_trousseau_perso_web.json').readAsStringSync())
        as Map<String, dynamic>;
    final cle = Uint8List.fromList(List.generate(32, (i) => i));
    final aad = aadCopie('compte-1', 'conv-1');

    test('une copie écrite par le navigateur s’ouvre ici', () {
      expect(dechiffrerCopie(cle, vecteur['corps'] as String, aad), vecteur['clair']);
    });

    test('et la même copie s’écrit ici à l’octet près (même nonce)', () {
      expect(
          chiffrerCopie(cle, vecteur['clair'] as String, aad,
              nonceImpose: Uint8List.fromList(List.filled(12, 7))),
          vecteur['corps']);
    });

    test('refusée pour un autre compte ou un autre groupe', () {
      expect(() => dechiffrerCopie(cle, vecteur['corps'] as String, aadCopie('compte-2', 'conv-1')),
          throwsA(anything));
      expect(() => dechiffrerCopie(cle, vecteur['corps'] as String, aadCopie('compte-1', 'conv-2')),
          throwsA(anything));
    });
  });

  group('administrer un groupe (lot 5) et retrouver ses clés (lot 6)', () {
    late FauxServeurAdmin serveur;
    late Client alice;
    late Client bob;
    late Client carole;
    late Client dave;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      serveur = FauxServeurAdmin(
        {'alice': 'ADMIN', 'bob': 'MEMBER', 'carole': 'MEMBER'},
        {'alice': '100', 'bob': '200', 'carole': '300', 'dave': '400'},
      );
      serveur.cleVersion = 0;
      alice = Client('alice', serveur);
      bob = Client('bob', serveur);
      carole = Client('carole', serveur);
      dave = Client('dave', serveur);
      for (final c in [alice, bob, carole, dave]) {
        await c.demarrer();
      }
      // L'archive est ouverte pour Alice et Bob : leur clé maîtresse est là.
      await alice.coffre.rangerMaitresse(maitresseDe(1));
      await bob.coffre.rangerMaitresse(maitresseDe(2));
    });

    test('activer : seule l’administratrice, la clé 1 arrive chez chacun', () async {
      await expectLater(bob.fil.groupe.activer('g1'), throwsA(isA<ApiException>()));
      final r = await alice.fil.groupe.activer('g1');
      expect(r.deja, isFalse);
      expect(r.bilan!.appareils, 2, reason: 'Bob et Carole, un appareil chacun');
      await bob.fil.relever();
      await carole.fil.relever();
      expect((await bob.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
      expect((await carole.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
      // Une seconde activation : « déjà », sans nouvelle clé.
      expect((await alice.fil.groupe.activer('g1')).deja, isTrue);
    });

    test('ajouter : Dave reçoit tout le trousseau et lit l’historique', () async {
      await alice.fil.groupe.activer('g1');
      final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'avant Dave');
      serveur.membres['dave'] = 'MEMBER';
      final bilan = await alice.fil.groupe.partagerApresAjout('g1', ['400']);
      expect(bilan.appareils, 1);
      await dave.fil.relever();
      final m = serveur.messages[id]!;
      final (clair, _) = await dave.fil.groupe.lire(
          convId: 'g1', messageId: id, expediteurId: 'alice', chiffre: m['groupe'] as Map<String, dynamic>);
      expect(clair?.texte, 'avant Dave');
    });

    test('exclure : version 2 pour les restants, pas pour l’exclue', () async {
      await alice.fil.groupe.activer('g1');
      await bob.fil.relever();
      await carole.fil.relever();
      serveur.membres.remove('carole');
      final r = await alice.fil.groupe.changerCle('g1', 'EXCLUSION');
      expect(r!.version, 2);
      await bob.fil.relever();
      await carole.fil.relever();
      expect((await bob.fil.groupe.trousseau('g1')).map((v) => v.n), [1, 2]);
      expect((await carole.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
      // Un autre administrateur part de la version COURANTE du serveur (ici 5,
      // changée ailleurs entre-temps), pas de la plus haute qu'il connaît.
      serveur.cleVersion = 5;
      serveur.membres['bob'] = 'ADMIN';
      expect(await bob.fil.groupe.changerCle('g1', 'MANUEL').then((x) => x?.version), 6);
    });

    test('la copie : déposée chiffrée, rien de lisible pour le serveur', () async {
      await alice.fil.groupe.activer('g1');
      await bob.fil.relever();
      await attendre(() => serveur.copies.containsKey('alice') && serveur.copies.containsKey('bob'));
      expect(serveur.copies.keys, containsAll(['alice', 'bob']));
      expect(serveur.copies.containsKey('carole'), isFalse, reason: 'archive fermée chez Carole');
      final cle = base64.encode((await bob.fil.groupe.trousseau('g1')).single.cle);
      expect(serveur.copies['bob']!.contains(cle), isFalse);
    });

    test('nouveau téléphone : Bob reprend ses clés et relit l’historique', () async {
      await alice.fil.groupe.activer('g1');
      await bob.fil.relever();
      final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'historique');
      await attendre(() => serveur.copies.containsKey('bob'));

      // Un second appareil de Bob : coffre vierge, même clé d'archive.
      final bob2 = Client('bob', serveur, stockage: 'bob-telephone-neuf');
      await bob2.demarrer();
      await bob2.coffre.rangerMaitresse(maitresseDe(2));
      expect(await bob2.fil.groupe.trousseau('g1'), isEmpty);
      expect(await bob2.fil.groupe.restaurerTous(), 1);
      expect((await bob2.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
      final m = serveur.messages[id]!;
      final (clair, _) = await bob2.fil.groupe.lire(
          convId: 'g1', messageId: id, expediteurId: 'alice', chiffre: m['groupe'] as Map<String, dynamic>);
      expect(clair?.texte, 'historique');
    });

    test('nouveau téléphone, à la demande : la clé manquante est reprise en lisant', () async {
      await alice.fil.groupe.activer('g1');
      await bob.fil.relever();
      final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'à la demande');
      await attendre(() => serveur.copies.containsKey('bob'));
      final bob2 = Client('bob', serveur, stockage: 'bob-autre');
      await bob2.demarrer();
      await bob2.coffre.rangerMaitresse(maitresseDe(2));
      final m = serveur.messages[id]!;
      final (clair, _) = await bob2.fil.groupe.lire(
          convId: 'g1', messageId: id, expediteurId: 'alice', chiffre: m['groupe'] as Map<String, dynamic>);
      expect(clair?.texte, 'à la demande');
    });

    test('repli APPAREIL : sans copie, un autre de mes appareils renvoie la clé', () async {
      await alice.fil.groupe.activer('g1');
      await bob.fil.relever();
      final id = await alice.fil.envoyer(convId: 'g1', pairId: null, texte: 'par un autre appareil');
      // Un second téléphone de Bob, SANS archive : aucune copie ne l'aidera.
      final bob2 = Client('bob', serveur, stockage: 'bob-sans-archive');
      await bob2.demarrer();
      final m = serveur.messages[id]!;
      Future<String?> lire() async => (await bob2.fil.groupe.lire(
              convId: 'g1', messageId: id, expediteurId: 'alice', chiffre: m['groupe'] as Map<String, dynamic>))
          .$1
          ?.texte;
      expect(await lire(), isNull, reason: 'pas encore de clé : la demande part');
      // La demande part en tâche de fond : on attend son dépôt (hors fil).
      await attendre(() => serveur.enveloppes
          .any((e) => e['expediteurId'] == 'bob' && e['destinataireId'] == 'bob' && e['messageId'] == null));
      await bob.fil.relever(); // le premier téléphone reçoit la demande, et répond
      await bob2.fil.relever(); // le second reçoit le trousseau
      expect((await bob2.fil.groupe.trousseau('g1')).map((v) => v.n), [1]);
      expect(await lire(), 'par un autre appareil');
    });

    test('une demande venue d’un AUTRE compte est refusée', () async {
      await alice.fil.groupe.activer('g1');
      await bob.fil.relever();
      await carole.fil.relever();
      // Carole adresse une demande… au téléphone de Bob.
      final api = serveur.pour('carole');
      final appareils = await carole.service.ouvrirSessions('bob');
      final enveloppes = [
        for (final d in appareils)
          () async {
            final e = await carole.service.chiffrer('bob', d, ecrireDemandeTrousseau('g1'));
            return {'destinataireId': 'bob', 'destinataireDevice': d, 'type': e.type, 'corps': e.corps};
          }(),
      ];
      await api('POST', '/api/e2ee/enveloppes', {
        'convId': 'g1',
        'deviceId': await carole.coffre.deviceId(),
        'enveloppes': await Future.wait(enveloppes),
      });
      final avant = serveur.enveloppes.where((e) => e['expediteurId'] == 'bob').length;
      await bob.fil.relever();
      expect(serveur.enveloppes.where((e) => e['expediteurId'] == 'bob').length, avant,
          reason: 'Bob ne doit rien envoyer à un autre compte');
    });

    test('une autre archive (mauvaise clé maîtresse) n’ouvre pas la copie', () async {
      await alice.fil.groupe.activer('g1');
      await bob.fil.relever();
      await attendre(() => serveur.copies.containsKey('bob'));
      final intrus = Client('bob', serveur, stockage: 'bob-intrus');
      await intrus.demarrer();
      await intrus.coffre.rangerMaitresse(maitresseDe(99));
      expect(await intrus.fil.groupe.restaurerTous(), 0);
      expect(await intrus.fil.groupe.trousseau('g1'), isEmpty);
    });
  });
}
