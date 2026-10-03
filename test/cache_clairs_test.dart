// CE QUE LE CACHE LOCAL GARDE QUAND LE SERVEUR RÉPOND — `cache_clairs.dart`.
//
// Défaut trouvé le 28/09/2026 : ouvrir une conversation chiffrée vidait le fil
// du cache avant d'y ranger la dernière page du serveur ; remonter l'historique
// remplaçait chaque ligne par sa version sans texte. Les textes déchiffrés, qui
// n'existent que sur l'appareil, disparaissaient.

import 'package:alanya/core/cache_clairs.dart';
import 'package:alanya/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

final _base = DateTime.utc(2026, 9, 28, 10);

Message _msg(
  String id,
  int minute, {
  String? texte,
  bool chiffre = true,
  bool supprime = false,
}) => Message(
  id: id,
  convId: 'c',
  senderId: 'bob',
  content: texte,
  type: 'TEXT',
  status: 'DELIVERED',
  replyToId: null,
  media: const [],
  createdAt: _base.add(Duration(minutes: minute)),
  deletedAt: supprime ? _base.add(const Duration(hours: 1)) : null,
  chiffre: chiffre,
);

LigneCache _ligne(
  String id,
  int minute, {
  String? texte,
  bool chiffre = true,
}) => LigneCache(
  id: id,
  content: texte,
  createdAt: _base.add(Duration(minutes: minute)),
  chiffre: chiffre,
);

void main() {
  group('planRemplacement (ouverture du fil)', () {
    test('un texte chiffré PLUS ANCIEN que la page est gardé', () {
      final plan = planRemplacement(
        [
          _ligne('vieux', 1, texte: 'bonjour'),
          _ligne('p1', 10, texte: 'salut'),
        ],
        [_msg('p1', 10)],
      );
      expect(plan.aEffacer, isEmpty);
    });

    test('la page arrive sans texte : le texte connu est recollé', () {
      final plan = planRemplacement(
        [_ligne('p1', 10, texte: 'salut')],
        [_msg('p1', 10)],
      );
      expect(plan.textes, {'p1': 'salut'});
    });

    test('un message supprimé pour tous perd son texte', () {
      final plan = planRemplacement(
        [_ligne('p1', 10, texte: 'secret')],
        [_msg('p1', 10, supprime: true)],
      );
      expect(plan.textes, isEmpty, reason: 'la ligne est écrite sans texte');
    });

    test(
      'absent de la page mais PLUS RÉCENT que son début : effacé (masqué, expiré)',
      () {
        final plan = planRemplacement(
          [
            _ligne('p1', 10, texte: 'a'),
            _ligne('parti', 12, texte: 'b'),
            _ligne('p2', 15),
          ],
          [_msg('p1', 10), _msg('p2', 15)],
        );
        expect(plan.aEffacer, {'parti'});
      },
    );

    test(
      'un message ORDINAIRE plus ancien que la page est effacé, comme avant',
      () {
        final plan = planRemplacement(
          [_ligne('vieux', 1, texte: 'x', chiffre: false)],
          [_msg('p1', 10, texte: 'y', chiffre: false)],
        );
        expect(
          plan.aEffacer,
          {'vieux'},
          reason: 'le serveur le garde : pas de raison de le conserver ici',
        );
      },
    );

    test('une ligne chiffrée SANS texte, plus ancienne, est effacée', () {
      final plan = planRemplacement([_ligne('vide', 1)], [_msg('p1', 10)]);
      expect(plan.aEffacer, {'vide'});
    });

    test('page vide : tout est effacé', () {
      final plan = planRemplacement([
        _ligne('vieux', 1, texte: 'bonjour'),
      ], const []);
      expect(plan.aEffacer, {'vieux'});
    });

    test('le serveur a le texte (fil ordinaire) : il fait foi', () {
      final plan = planRemplacement(
        [_ligne('p1', 10, texte: 'ancien', chiffre: false)],
        [_msg('p1', 10, texte: 'modifié', chiffre: false)],
      );
      expect(plan.textes, isEmpty);
    });

    test('dates de fuseaux différents : comparées comme des instants', () {
      // 11 h à Yaoundé (UTC+1) = 10 h UTC : AVANT 10 h 05 UTC.
      final local = DateTime.utc(2026, 9, 28, 10).toLocal();
      final plan = planRemplacement(
        [
          LigneCache(
            id: 'vieux',
            content: 'x',
            createdAt: local,
            chiffre: true,
          ),
        ],
        [_msg('p1', 5)],
      );
      expect(plan.aEffacer, isEmpty);
    });
  });

  group('dateCache / dateNormalisee (une seule forme de date)', () {
    test('une date locale et sa forme UTC donnent la MÊME chaîne', () {
      final instant = DateTime.utc(2026, 9, 28, 9, 14, 36, 123);
      expect(dateCache(instant.toLocal()), dateCache(instant));
      expect(dateCache(instant), '2026-09-28T09:14:36.123Z');
    });

    test('les microsecondes sont retirées : largeur constante', () {
      final d = DateTime.utc(2026, 9, 28, 9, 14, 36, 123, 456);
      expect(dateCache(d), '2026-09-28T09:14:36.123Z');
    });

    test(
      'une ancienne ligne écrite en heure du téléphone est ramenée en UTC',
      () {
        final instant = DateTime.utc(2026, 9, 28, 9, 14, 36);
        final brute = instant.toLocal().toIso8601String(); // sans « Z »
        expect(brute.endsWith('Z'), isFalse);
        expect(dateNormalisee(brute), dateCache(instant));
      },
    );

    test('l’ordre des chaînes est celui des instants', () {
      // Le défaut d'origine : « 10:14 » local passait après « 09:30Z ».
      final releve = DateTime.utc(2026, 9, 28, 9, 14).toLocal();
      final serveur = DateTime.utc(2026, 9, 28, 9, 30);
      expect(dateCache(releve).compareTo(dateCache(serveur)), lessThan(0));
    });
  });

  group('texteAEcrire (upsert, page ancienne)', () {
    test('sans texte serveur : le texte connu reste', () {
      expect(texteAEcrire(_msg('a', 1), 'bonjour'), 'bonjour');
    });
    test('le serveur a un texte : il gagne', () {
      expect(texteAEcrire(_msg('a', 1, texte: 'neuf'), 'vieux'), 'neuf');
    });
    test('supprimé pour tous : plus de texte', () {
      expect(texteAEcrire(_msg('a', 1, supprime: true), 'secret'), isNull);
    });
    test('rien de connu : rien d’inventé', () {
      expect(texteAEcrire(_msg('a', 1), null), isNull);
    });
  });
}
