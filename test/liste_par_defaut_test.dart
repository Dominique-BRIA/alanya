import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/models/contact_list.dart';

/// Spécification exécutable d'UNE règle : **une liste semée avec le compte se
/// reconnaît à sa clé, et cette clé vient du serveur sous le nom `cle`.**
///
/// Pourquoi ce fichier. La première écriture de cette fonctionnalité lisait
/// `parDefaut`, un booléen que l'API n'envoie pas — `fromJson` retombait donc
/// sur `false` pour TOUTES les listes, y compris les quatre listes d'origine.
/// Rien ne le signalait : le champ existait, le code compilait, l'écran
/// s'affichait, et le bouton « Supprimer » restait simplement offert partout.
/// La panne ne se voyait qu'en le touchant, sur un vrai compte, pour recevoir
/// un 409 du serveur.
///
/// ⚠️ C'EST UN CONTRÔLE DE CONTRAT, pas de logique : il fige le NOM du champ
/// JSON. Une faute de frappe y est invisible au compilateur, Dart lisant une
/// `Map<String, dynamic>` — c'est exactement la classe de défaut qui vient de
/// se produire.
///
/// Lancer avec : flutter test test/liste_par_defaut_test.dart
void main() {
  /// Le minimum qu'une liste porte, pour n'écrire que ce que le cas teste.
  Map<String, dynamic> ligne({String? cle}) => {
        "id": "l1",
        "name": "Bureau",
        "ringtone": null,
        "color": null,
        if (cle != null) "cle": cle,
        "createdAt": "2026-09-11T10:00:00.000Z",
        "members": <Map<String, dynamic>>[],
      };

  group("La clé des listes d'origine", () {
    test("se lit dans le champ `cle` du serveur", () {
      final l = ListeContacts.fromJson(ligne(cle: "bureau"));
      expect(l.cle, "bureau");
      expect(l.estParDefaut, isTrue);
    });

    test("les quatre clés semées sont reconnues", () {
      for (final c in ["bureau", "amis", "confiance", "famille"]) {
        expect(ListeContacts.fromJson(ligne(cle: c)).estParDefaut, isTrue,
            reason: "« $c » est semée avec le compte");
      }
    });

    test("une liste faite par l'utilisateur n'en a pas", () {
      final l = ListeContacts.fromJson(ligne());
      expect(l.cle, isNull);
      expect(l.estParDefaut, isFalse);
    });

    test("`cle: null` explicite vaut liste ordinaire", () {
      final j = ligne()..["cle"] = null;
      expect(ListeContacts.fromJson(j).estParDefaut, isFalse);
    });

    // ⚠️ Le repli doit rendre la liste SUPPRIMABLE, et non l'inverse : face à
    // un serveur qui ne connaît pas encore ce champ, se taire et tout
    // verrouiller retirerait à l'utilisateur un geste qui lui est permis.
    test("un serveur antérieur au champ laisse tout supprimable", () {
      final ancien = ligne()..remove("cle");
      expect(ListeContacts.fromJson(ancien).estParDefaut, isFalse);
    });

    // 🔴 LE DÉFAUT EXACT QUI VIENT D'ÊTRE CORRIGÉ. `parDefaut` était le nom
    // supposé ; le serveur n'envoie que `cle`. Si quelqu'un revient au booléen,
    // ce contrôle tombe.
    test("`parDefaut` n'est PAS le nom du champ", () {
      final faux = ligne()..["parDefaut"] = true;
      expect(ListeContacts.fromJson(faux).estParDefaut, isFalse,
          reason: "seul `cle` fait foi");
    });
  });
}
