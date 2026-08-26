import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/core/telephone.dart';

/// Miroir des contrôles de `backend-alanya/src/lib/telephone.mjs`.
///
/// ⚠️ LES MÊMES CAS, AVEC LES MÊMES ATTENDUS, volontairement. C'est ce qui
/// prouve que les deux implémentations ne divergent pas — et la divergence
/// silencieuse entre clients est exactement ce qui a bloqué les appels
/// Web → Android pendant des jours.
void main() {
  group("normaliserTelephone — les saisies possibles du MÊME numéro", () {
    const attendu = "+237691234567";

    test("national, dicté", () {
      expect(normaliserTelephone("6 91 23 45 67", "+237"), attendu);
    });
    test("national, collé", () {
      expect(normaliserTelephone("691234567", "+237"), attendu);
    });
    test("avec le zéro de service", () {
      expect(normaliserTelephone("0691234567", "+237"), attendu);
    });
    test("déjà international", () {
      expect(normaliserTelephone("+237 691 23 45 67", "+237"), attendu);
    });
    test("international en 00", () {
      expect(normaliserTelephone("00237691234567", "+237"), attendu);
    });

    test("LA propriété : quatre saisies → UNE seule forme", () {
      final formes = {
        normaliserTelephone("6 91 23 45 67", "+237"),
        normaliserTelephone("0691234567", "+237"),
        normaliserTelephone("+237691234567", "+237"),
        normaliserTelephone("00237691234567", "+237"),
      };
      expect(formes.length, 1);
    });
  });

  group("normaliserTelephone — les vides", () {
    test("saisie vide", () => expect(normaliserTelephone("", "+237"), ""));
    test("que des séparateurs",
        () => expect(normaliserTelephone("  -- ", "+237"), ""));
    test("que des zéros", () => expect(normaliserTelephone("000", "+237"), ""));
    test("sans indicatif de pays",
        () => expect(normaliserTelephone("0691234567", ""), "+691234567"));
  });

  test("indicatif redoublé : laissé tel quel, pas deviné", () {
    // Voir la note du module : le retirer en boucle mutilerait un numéro
    // national commençant par les chiffres de son propre indicatif.
    expect(normaliserTelephone("+237237691234567", "+237"), "+237237691234567");
  });

  group("numéro d'un AUTRE pays que celui du compte", () {
    // 🔴 Le cas qui a coûté un numéro faux le 26/08/2026 : sans la sortie
    // anticipée sur le « + », l'indicatif du compte se collait devant un
    // numéro étranger, qui devenait injoignable.
    test("numéro sénégalais sur un compte français", () {
      expect(normaliserTelephone("+221 34543678", "+33"), "+22134543678");
    });
    test("ligne camerounaise sur un compte français", () {
      expect(normaliserTelephone("+237 6 91 23 45 67", "+33"), "+237691234567");
    });
    test("sans « + », le numéro reste national", () {
      expect(normaliserTelephone("612345678", "+33"), "+33612345678");
    });
  });

  group("formaterTelephone — le groupement local", () {
    test("Cameroun : paires depuis la fin", () {
      expect(formaterTelephone("691234567", "+237", "CM"), "+237 6 91 23 45 67");
    });
    test("France : 9 chiffres, même règle", () {
      expect(formaterTelephone("0612345678", "+33", "FR"), "+33 6 12 34 56 78");
    });
    test("États-Unis : 3-3-4", () {
      expect(formaterTelephone("4155552671", "+1", "US"), "+1 415 555 2671");
    });
    test("Canada : 3-3-4 aussi", () {
      expect(formaterTelephone("4165551234", "+1", "CA"), "+1 416 555 1234");
    });
    test("Royaume-Uni : 4-6", () {
      expect(formaterTelephone("07700900123", "+44", "GB"), "+44 7700 900123");
    });
    test("pays sans règle propre → paires", () {
      expect(formaterTelephone("771234567", "+221", "SN"), "+221 7 71 23 45 67");
    });
    test("iso2 absent → paires", () {
      expect(formaterTelephone("771234567", "+221", null), "+221 7 71 23 45 67");
    });
    test("plus long qu'annoncé : rien n'est coupé", () {
      expect(formaterTelephone("41555526719", "+1", "US"), "+1 415 555 2671 9");
    });
    test("vide reste vide", () {
      expect(formaterTelephone("", "+237", "CM"), "");
    });
  });

  group("numéro portant DÉJÀ un autre indicatif que celui demandé", () {
    // 🔴 Ces trois-là échouaient avant le correctif du 26/08/2026 : le
    // découpage réattribuait les chiffres et rendait un AUTRE numéro.
    // Découvert en ajoutant le choix du pays de la ligne dans les réglages —
    // changer ce sélecteur réécrivait le numéro déjà saisi.
    test("ligne française présentée avec l'indicatif camerounais", () {
      expect(formaterTelephone("+33612345678", "+237", "CM"), "+33612345678");
    });
    test("ligne sénégalaise présentée avec l'indicatif français", () {
      expect(formaterTelephone("+221 34 543 678", "+33", "FR"), "+22134543678");
    });
    test("aucun chiffre perdu : le formatage reste réversible", () {
      expect(
        normaliserTelephone(formaterTelephone("+33612345678", "+237", "CM"), "+237"),
        "+33612345678",
      );
    });
  });

  test("formater n'altère jamais ce qu'on envoie", () {
    const canonique = "+237691234567";
    expect(
      normaliserTelephone(formaterTelephone(canonique, "+237", "CM"), "+237"),
      canonique,
    );
  });
}
