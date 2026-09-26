import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/texte_recherche.dart';

/// Spécification exécutable du tri et de la recherche du carnet d'adresses.
///
/// Lancer avec : flutter test test/texte_recherche_test.dart
void main() {
  group(
      "Tri alphabétique — les accents ne doivent pas reléguer en fin de liste",
      () {
    test("Émile se classe entre Denis et Fabrice, pas après Zoé", () {
      final noms = ["Zoé", "Denis", "Émile", "Fabrice", "Ana"];
      noms.sort(comparePourTri);
      expect(noms, ["Ana", "Denis", "Émile", "Fabrice", "Zoé"]);
    });

    test("sans normalisation, Dart placerait É après Z — c'est le défaut évité",
        () {
      // Le tri NAÏF, montré pour que la raison d'être du helper reste visible.
      final naif = ["Zoé", "Émile"]..sort();
      expect(naif, ["Zoé", "Émile"]);
      // Le tri corrigé remet l'ordre attendu par un lecteur humain.
      final corrige = ["Zoé", "Émile"]..sort(comparePourTri);
      expect(corrige, ["Émile", "Zoé"]);
    });

    test("la casse n'influence pas le classement", () {
      final noms = ["bernard", "Alice", "CÉDRIC"];
      noms.sort(comparePourTri);
      expect(noms, ["Alice", "bernard", "CÉDRIC"]);
    });

    test("ordre STABLE entre homonymes accentués et non accentués", () {
      // Sans départage par la valeur brute, ces deux-là changeraient de place
      // d'un rafraîchissement à l'autre.
      final a = ["Émile", "Emile"]..sort(comparePourTri);
      final b = ["Emile", "Émile"]..sort(comparePourTri);
      expect(a, b);
    });
  });

  group("Recherche — on tape sans accent, on trouve quand même", () {
    test("« emile » trouve « Émile »", () {
      expect(contientRecherche("Émile", "emile"), isTrue);
    });

    test("« FRANCOIS » trouve « François »", () {
      expect(contientRecherche("François", "FRANCOIS"), isTrue);
    });

    test("la recherche porte sur une partie du nom", () {
      expect(contientRecherche("Jean-Baptiste Ngoué", "baptiste"), isTrue);
      expect(contientRecherche("Jean-Baptiste Ngoué", "ngoue"), isTrue);
    });

    test("une requête vide ne filtre rien", () {
      expect(contientRecherche("n'importe qui", ""), isTrue);
      expect(contientRecherche("n'importe qui", "   "), isTrue);
    });

    test("ce qui ne correspond pas est bien écarté", () {
      expect(contientRecherche("Émile", "zoe"), isFalse);
    });
  });

  group("Cas limites", () {
    test("ligatures françaises", () {
      expect(normaliseTexte("Cœur"), "coeur");
      expect(contientRecherche("Cœur", "coeur"), isTrue);
    });

    test("chaîne vide", () {
      expect(normaliseTexte(""), "");
      expect(comparePourTri("", ""), 0);
    });

    test("les chiffres d'un Alanya ID passent inchangés", () {
      expect(normaliseTexte("67 64 15 99"), "67 64 15 99");
    });
  });
}
