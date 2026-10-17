// MÉDIAS CHIFFRÉS — le mobile lit et écrit EXACTEMENT les mêmes octets que le
// web, et refuse ce que le web refuse.
//
// Le vecteur `test/donnees/vecteur_media.json` est produit par le module web
// (`STAGE-WEB/scripts/e2ee-media-vecteur.mjs`). S'il diverge d'un octet, un
// média envoyé d'un côté ne s'ouvre plus de l'autre.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _motif(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 7 + 3) & 255));

void main() {
  final vecteur =
      jsonDecode(File('test/donnees/vecteur_media.json').readAsStringSync())
          as Map<String, dynamic>;
  final cas = (vecteur['cas'] as List).cast<Map<String, dynamic>>();
  final cleFixe = Uint8List.fromList(List<int>.generate(32, (i) => i));

  group('parité avec le web (vecteur)', () {
    for (final c in cas) {
      final taille = c['taille'] as int;
      test('$taille octets : même chiffré, même empreinte', () {
        final f = chiffrerFichier(_motif(taille), cleImposee: cleFixe);
        expect(base64Encode(f.chiffre), c['chiffre']);
        expect(f.empreinte, c['empreinte']);
        expect(f.cle, c['cle']);
      });
      test('$taille octets : le chiffré du web se déchiffre ici', () {
        final clair = dechiffrerFichier(
          base64Decode(c['chiffre'] as String),
          cle: c['cle'] as String,
          empreinte: c['empreinte'] as String,
          taille: taille,
        );
        expect(clair, _motif(taille));
      });
    }

    test('la charge écrite par le web se lit ici', () {
      final ch = lireCharge(
        vecteur['charge'] as String,
        '11111111-2222-3333-4444-555555555555',
      );
      expect(ch.texte, 'légende 😀');
      expect(ch.media!.id, '66666666-7777-8888-9999-000000000000');
      expect(ch.media!.largeur, 640);
      expect(ch.media!.mime, 'image/jpeg');
    });
  });

  group('attaques', () {
    final clair = _motif(tailleBloc * 2 + 500);
    final f = chiffrerFichier(clair);
    String sha(Uint8List o) => base64Encode(empreinteDe(o));

    test('deux blocs inversés : refusé, même empreinte recalculée', () {
      const b = tailleBloc + 16;
      final inv = Uint8List.fromList(f.chiffre);
      inv.setRange(0, b, f.chiffre, b);
      inv.setRange(b, 2 * b, f.chiffre, 0);
      expect(
        () => dechiffrerFichier(
          inv,
          cle: f.cle,
          empreinte: sha(inv),
          taille: clair.length,
        ),
        throwsA(isA<FichierInvalide>()),
      );
    });

    test('dernier bloc retiré : refusé', () {
      const b = tailleBloc + 16;
      final coupe = Uint8List.sublistView(f.chiffre, 0, 2 * b);
      expect(
        () => dechiffrerFichier(
          coupe,
          cle: f.cle,
          empreinte: sha(coupe),
          taille: 2 * tailleBloc,
        ),
        throwsA(isA<FichierInvalide>()),
      );
    });

    test('mauvaise clé, empreinte ou taille : refusé', () {
      final autre = chiffrerFichier(clair);
      expect(
        () => dechiffrerFichier(
          f.chiffre,
          cle: autre.cle,
          empreinte: f.empreinte,
          taille: clair.length,
        ),
        throwsA(isA<FichierInvalide>()),
      );
      expect(
        () => dechiffrerFichier(
          f.chiffre,
          cle: f.cle,
          empreinte: autre.empreinte,
          taille: clair.length,
        ),
        throwsA(isA<FichierInvalide>()),
      );
      expect(
        () => dechiffrerFichier(
          f.chiffre,
          cle: f.cle,
          empreinte: f.empreinte,
          taille: 3,
        ),
        throwsA(isA<FichierInvalide>()),
      );
    });

    test('charge rattachée à un autre message : refusée', () {
      const id = '11111111-2222-3333-4444-555555555555';
      expect(
        () => lireCharge(ecrireCharge(id, 'x'), 'autre'),
        throwsA(isA<ChargeInvalide>()),
      );
      expect(
        () => lireCharge(ecrireCharge(id, 'x'), null),
        throwsA(isA<ChargeInvalide>()),
      );
    });

    test('un texte qui imite une charge reste un texte', () {
      const piege = '{"v":2,"id":"x","texte":"piège"}';
      expect(lireCharge(piege, 'm').texte, piege);
    });
  });
}
