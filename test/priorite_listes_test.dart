import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/sonneries_listes.dart';
import 'package:alanya/models/contact_list.dart';

/// L'ORDRE DE PRIORITÉ DES LISTES, qui décide quelle sonnerie gagne.
///
/// Cette règle est pure et se vérifie sans écran ni réseau — c'est pourquoi
/// elle vit dans une fonction à part. Elle doit rester la transposition EXACTE
/// d'`ORDRE_LISTES` côté serveur (`ordre ASC NULLS LAST, createdAt ASC,
/// id ASC`) : une divergence ferait sonner le même correspondant différemment
/// sur le téléphone et dans le navigateur, sans que rien à l'écran l'explique.
ListeContacts _liste({
  required String id,
  required String nom,
  int? ordre,
  String cree = "2026-01-01T00:00:00Z",
}) => ListeContacts(
  id: id,
  name: nom,
  ringtone: null,
  ringtoneMessage: null,
  ordre: ordre,
  color: null,
  cle: null,
  createdAt: DateTime.parse(cree),
  members: const [],
);

void main() {
  group('comparePriorite', () {
    test('le rang choisi prime sur tout le reste', () {
      final premiere = _liste(id: "b", nom: "Zoulou", ordre: 0);
      final seconde = _liste(id: "a", nom: "Amis", ordre: 1);
      expect(SonneriesDeListes.comparePriorite(premiere, seconde), lessThan(0));
      expect(
        SonneriesDeListes.comparePriorite(seconde, premiere),
        greaterThan(0),
      );
    });

    test('une liste SANS rang tombe en dernier, jamais en tête', () {
      final rangee = _liste(id: "a", nom: "Zoulou", ordre: 9);
      final sansRang = _liste(id: "b", nom: "Amis");
      // Même avec un rang très élevé et un nom qui la placerait après en
      // alphabétique, la liste ordonnée passe devant : c'est le piège
      // `NULLS LAST`, et l'inverse est ce que PostgreSQL ferait par défaut.
      expect(SonneriesDeListes.comparePriorite(rangee, sansRang), lessThan(0));
      expect(
        SonneriesDeListes.comparePriorite(sansRang, rangee),
        greaterThan(0),
      );
    });

    test('à rang égal, la plus ancienne gagne', () {
      final ancienne = _liste(
        id: "z",
        nom: "Zoulou",
        ordre: 2,
        cree: "2026-01-01T00:00:00Z",
      );
      final recente = _liste(
        id: "a",
        nom: "Amis",
        ordre: 2,
        cree: "2026-06-01T00:00:00Z",
      );
      expect(SonneriesDeListes.comparePriorite(ancienne, recente), lessThan(0));
    });

    test('à rang ET âge égaux, c\'est l\'identifiant qui départage', () {
      final a = _liste(id: "aaa", nom: "Zoulou", ordre: 1);
      final b = _liste(id: "bbb", nom: "Amis", ordre: 1);
      // ⚠️ Sur l'IDENTIFIANT et non sur le nom : renommer une liste ne doit pas
      // déplacer la sonnerie de quelqu'un.
      expect(SonneriesDeListes.comparePriorite(a, b), lessThan(0));
    });

    test('sans aucun rang, le tri se réduit à l\'ancienneté d\'avant', () {
      // C'est l'état de tous les comptes tant que personne n'a rien ordonné :
      // le changement doit être invisible jusqu'au premier réordonnancement.
      final vieille = _liste(
        id: "z",
        nom: "Zoulou",
        cree: "2026-01-01T00:00:00Z",
      );
      final neuve = _liste(id: "a", nom: "Amis", cree: "2026-06-01T00:00:00Z");
      expect(SonneriesDeListes.comparePriorite(vieille, neuve), lessThan(0));
    });

    test('un tri complet respecte rang, puis âge, puis identifiant', () {
      final listes = [
        _liste(id: "d", nom: "Amis", cree: "2026-02-01T00:00:00Z"),
        _liste(id: "c", nom: "Bureau", ordre: 1, cree: "2026-05-01T00:00:00Z"),
        _liste(id: "b", nom: "Famille", cree: "2026-01-01T00:00:00Z"),
        _liste(
          id: "a",
          nom: "Confiance",
          ordre: 0,
          cree: "2026-06-01T00:00:00Z",
        ),
      ]..sort(SonneriesDeListes.comparePriorite);
      // Les deux ordonnées d'abord, dans leur rang ; les deux autres ensuite,
      // par ancienneté. Un tri alphabétique aurait rendu Amis, Bureau,
      // Confiance, Famille — soit une gagnante différente.
      expect(listes.map((l) => l.id).toList(), ["a", "c", "b", "d"]);
    });

    test('le tri est stable d\'un appel à l\'autre', () {
      // La sonnerie ne doit pas changer d'un message au suivant : deux tris du
      // même ensemble, dans des ordres de départ différents, doivent rendre le
      // même résultat.
      final base = [
        _liste(id: "a", nom: "Amis", ordre: 2),
        _liste(id: "b", nom: "Bureau"),
        _liste(id: "c", nom: "Confiance", ordre: 2),
      ];
      final sens1 = List.of(base)..sort(SonneriesDeListes.comparePriorite);
      final sens2 = List.of(base.reversed)
        ..sort(SonneriesDeListes.comparePriorite);
      expect(sens1.map((l) => l.id).toList(), sens2.map((l) => l.id).toList());
    });
  });
}
