import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/features/home/filtre_conversations.dart';

/// Spécification exécutable du filtre de la liste des conversations.
///
/// Les règles viennent du web (`chats.tsx`) et doivent être IDENTIQUES : sans
/// cela, « Famille » ne désignerait pas le même ensemble d'un écran à l'autre.
///
/// Lancer avec : flutter test test/filtre_conversations_test.dart
void main() {
  const moi = "u-moi";
  final filtre = MembresDuFiltre({"u-papa", "u-maman"}, {"67641599"});

  List<({String id, String numero})> avec(List<List<String>> gens) =>
      gens.map((g) => (id: g[0], numero: g[1])).toList();

  group("Une liste rassemble des PERSONNES, pas des salons", () {
    test("un tête-à-tête avec un membre est dans la liste", () {
      expect(
        estDansListe(
          estGroupe: false,
          membres: avec([
            ["u-moi", "10000001"],
            ["u-papa", "20000002"]
          ]),
          monId: moi,
          filtre: filtre,
        ),
        isTrue,
      );
    });

    test(
        "🔴 un GROUPE n'est JAMAIS dans une liste, même s'il en contient un membre",
        () {
      expect(
        estDansListe(
          estGroupe: true,
          membres: avec([
            ["u-moi", "10000001"],
            ["u-papa", "20000002"]
          ]),
          monId: moi,
          filtre: filtre,
        ),
        isFalse,
      );
    });

    test("« Moi » (un seul participant) n'est le cercle de personne", () {
      expect(
        estDansListe(
          estGroupe: false,
          membres: avec([
            ["u-moi", "10000001"]
          ]),
          monId: moi,
          filtre: filtre,
        ),
        isFalse,
      );
    });

    test("un tête-à-tête avec quelqu'un d'absent de la liste est écarté", () {
      expect(
        estDansListe(
          estGroupe: false,
          membres: avec([
            ["u-moi", "10000001"],
            ["u-inconnu", "30000003"]
          ]),
          monId: moi,
          filtre: filtre,
        ),
        isFalse,
      );
    });
  });

  group("Le numéro est un SECOND essai, pour les caches anciens", () {
    test("un membre sans identifiant connu est retrouvé par son numéro", () {
      expect(
        estDansListe(
          estGroupe: false,
          membres: avec([
            ["u-moi", "10000001"],
            ["", "67641599"]
          ]),
          monId: moi,
          filtre: filtre,
        ),
        isTrue,
      );
    });

    test("le numéro se compare SANS ses espaces", () {
      expect(
        estDansListe(
          estGroupe: false,
          membres: avec([
            ["u-moi", "10000001"],
            ["", "67 64 15 99"]
          ]),
          monId: moi,
          filtre: filtre,
        ),
        isTrue,
      );
      expect(chiffresSeuls("67 64 15 99"), "67641599");
    });

    test("l'identifiant est comparé en MINUSCULES, comme côté serveur", () {
      expect(
        estDansListe(
          estGroupe: false,
          membres: avec([
            ["u-moi", "1"],
            ["U-PAPA", "9"]
          ]),
          monId: moi,
          filtre: filtre,
        ),
        isTrue,
      );
    });
  });

  group("Un nom de liste ne peut pas usurper un filtre système", () {
    test("la clé d'une liste est PRÉFIXÉE", () {
      const f = FiltreConversations.liste("unread");
      expect(f.cle, "liste:unread");
      // Sans le préfixe, une liste nommée « unread » se confondrait avec le
      // filtre système du même nom — et l'identifiant vient du SERVEUR.
      expect(f.cle == FiltreSysteme.nonLues.name, isFalse);
      expect(f.estUneListe, isTrue);
    });

    test("un filtre système n'est pas préfixé", () {
      const f = FiltreConversations.systeme(FiltreSysteme.nonLues);
      expect(f.cle, "nonLues");
      expect(f.estUneListe, isFalse);
    });

    test("deux filtres identiques sont égaux — un seul actif à la fois", () {
      expect(const FiltreConversations.liste("a"),
          const FiltreConversations.liste("a"));
      expect(
          const FiltreConversations.liste("a") ==
              const FiltreConversations.liste("b"),
          isFalse);
    });
  });
}
