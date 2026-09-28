// LA CLÉ DE RÉCUPÉRATION — 12 mots parmi 2 048, soit 132 bits.
//
// 🐛 Elle en valait 60 (12 mots parmi 32), sans étirement : une copie de la
// base suffisait pour tout essayer hors ligne. Jumeau du web :
// `STAGE-WEB/scripts/e2ee-serrures-test.js`.

import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_serrures.dart';
import 'package:alanya/services/e2ee/mots_recuperation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la liste compte 2 048 mots distincts, a-z seulement', () {
    expect(motsRecuperation.length, 2048);
    expect(motsRecuperation.toSet().length, 2048);
    expect(motsRecuperation.every((m) => RegExp(r'^[a-z]+$').hasMatch(m)), isTrue);
  });

  test('une clé tirée : 12 mots, tous de la liste, et la liste entière sert', () {
    final liste = motsRecuperation.toSet();
    final tirages = List.generate(200, (_) => tirerCleRecuperation().split(' '));
    expect(tirages.every((t) => t.length == 12 && t.every(liste.contains)), isTrue);
    // 2 400 mots tirés : la liste de 32 n'en donnerait jamais plus de 32.
    expect(tirages.expand((t) => t).toSet().length, greaterThan(1000));
  });

  test('une clé de l’ANCIENNE liste ouvre toujours sa serrure', () {
    // La serrure dérive sa clé du TEXTE : changer de liste ne doit pas rendre
    // inutilisables les clés déjà distribuées.
    const ancienne =
        'tortue riviere lampe cousin fenetre orage sable guitare renard marbre pluie cerise';
    final maitresse = Uint8List.fromList(List.generate(32, (i) => i));
    final s = poserSerrure(maitresse, TypeSerrure.recuperation, ancienne);
    expect(ouvrirArchive(ancienne, s), maitresse);
  });

  test('une saisie en majuscules, mal espacée, avec accents, est normalisée', () {
    expect(normaliserCleRecuperation('  Abîme   ÉLÈVE \n'), 'abime eleve');
  });

  test('une clé tirée ressort INTACTE de la normalisation', () {
    // 🐛 Vécu en écrivant ce lot : un `\` perdu dans `RegExp(r'\s+')` faisait
    // découper sur la LETTRE « s ». Toute clé contenant un « s » était altérée,
    // et la récupération échouait — sans rien qui le dise.
    expect(normaliserCleRecuperation('sable silex saison'), 'sable silex saison');
    for (var i = 0; i < 200; i++) {
      final cle = tirerCleRecuperation();
      expect(normaliserCleRecuperation(cle.toUpperCase()), cle);
    }
  });
}
