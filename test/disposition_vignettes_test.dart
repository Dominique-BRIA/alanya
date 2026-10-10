import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/features/calls/disposition_vignettes.dart';

/// Spécification exécutable d'UNE règle : **la somme des rangées vaut toujours
/// le nombre de participants affichés.**
///
/// 🔴 POURQUOI CETTE RÈGLE ET PAS UNE AUTRE. L'écran d'appel découpe la liste
/// des participants rangée par rangée avec `sublist`. Une somme trop GRANDE
/// sort des bornes et lève une exception **en plein appel vidéo** ; une somme
/// trop PETITE fait disparaître quelqu'un de l'écran sans que rien ne le
/// signale — il parle, on l'entend, on ne le voit pas.
///
/// ⚠️ AUCUN AUTRE CONTRÔLE NE VOIT CE DÉFAUT. Le compilateur ne sait pas
/// additionner une liste de constantes, et la panne ne se produit qu'avec le
/// nombre exact de participants concerné : une disposition fausse pour cinq
/// personnes passe inaperçue tant que l'appel n'en réunit que quatre.
///
/// Lancer avec : flutter test test/disposition_vignettes_test.dart
void main() {
  group("La somme des rangées couvre exactement les participants", () {
    // Bien au-delà du seuil de défilement : la fonction doit rester totale,
    // même quand l'écran choisit une autre présentation.
    for (var n = 1; n <= 12; n++) {
      test("$n participant(s)", () {
        final rangees = dispositionVignettes(n);
        final total = rangees.fold<int>(0, (s, c) => s + c);
        // Au-delà du seuil, l'écran bascule sur une grille qui défile et
        // n'utilise plus ce découpage : on vérifie seulement qu'il reste sain.
        if (n <= maxVignettesSansDefilement) {
          expect(total, n,
              reason: "rangées $rangees pour $n participants — "
                  "sublist sortirait des bornes ou perdrait quelqu'un");
        }
        expect(rangees, isNotEmpty);
        expect(rangees.every((c) => c > 0), isTrue,
            reason: "une rangée vide occuperait de la hauteur pour rien");
      });
    }
  });

  group("Les choix de mise en page qui règlent le défaut signalé", () {
    // 🔴 LE CAS DE LA CAPTURE. Deux participants donnaient deux vignettes en
    // haut et un grand vide en dessous. Deux rangées d'une vignette, c'est
    // deux moitiés d'écran : plus de vide.
    test("à deux, deux rangées pleine largeur — et non deux colonnes", () {
      expect(dispositionVignettes(2), [1, 1]);
    });

    test("à trois, une grande au-dessus et deux au-dessous", () {
      expect(dispositionVignettes(3), [1, 2]);
    });

    test("à quatre, un carré régulier", () {
      expect(dispositionVignettes(4), [2, 2]);
    });

    // La dernière s'étale plutôt que de laisser un trou à côté d'elle.
    test("à cinq, la dernière prend toute la largeur", () {
      expect(dispositionVignettes(5).last, 1);
    });

    test("seul, une seule vignette plein écran", () {
      expect(dispositionVignettes(1), [1]);
    });
  });
}
