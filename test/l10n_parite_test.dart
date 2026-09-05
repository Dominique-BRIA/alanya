import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les 9 langues portent-elles exactement les mêmes clés ?
///
/// 🔴 AUCUN AUTRE CONTRÔLE NE VOIT CE DÉFAUT. `tr()` prend une chaîne : le
/// compilateur ne connaît pas les clés, et `AppLocalizations.get` retombe
/// silencieusement sur le français quand une langue n'a pas la sienne. Une clé
/// oubliée dans une seule langue passe donc `flutter analyze`, passe le build,
/// passe la revue — et ne se voit qu'en changeant la langue de l'application.
///
/// Le risque est réel et récent : les catalogues sont modifiés PAR SCRIPT quand
/// on ajoute une clé aux neuf blocs d'un coup. Un ancrage qui rate un bloc ne
/// se remarque pas, et le 26/08/2026 deux modifications de ce genre se sont
/// enchaînées.
///
/// ⚠️ CE TEST LIT LE FICHIER SOURCE, il n'importe pas la table : elle est
/// privée à sa bibliothèque, et l'exposer pour un test l'ouvrirait à tout le
/// reste du code. Il s'appuie donc sur la forme du fichier — une clé par ligne,
/// `'cle': 'valeur',` — qui est la convention tenue par tout le catalogue.
void main() {
  test("les 9 langues portent les mêmes clés", () {
    final fichier = File("lib/l10n/app_localizations.dart");
    expect(fichier.existsSync(), isTrue,
        reason: "le test doit tourner depuis la racine du paquet");

    final debutLangue = RegExp(r"^'([a-z]{2})': \{$");
    final uneCle = RegExp(r"^\s*'([A-Za-z0-9_]+)':\s");

    final parLangue = <String, Set<String>>{};
    String? courante;

    for (final ligne in fichier.readAsLinesSync()) {
      final entete = debutLangue.firstMatch(ligne);
      if (entete != null) {
        courante = entete.group(1);
        parLangue[courante!] = <String>{};
        continue;
      }
      if (courante == null) continue;
      // 🔴 LE DERNIER BLOC SE FERME PAR « } », SANS VIRGULE — c'est le dernier
      // de la table, il n'a rien après lui. Ne reconnaître que « }, » laissait
      // donc le norvégien OUVERT jusqu'à la fin du fichier, et tout ce qui
      // ressemble à `'cle': …` plus bas lui était attribué : la ligne
      // `'n': '$n',` de l'aide `trN` s'est ainsi retrouvée comptée comme une
      // clé norvégienne absente du français.
      //
      // « }; » ferme la table elle-même : au-delà, plus aucune clé à lire.
      final fin = ligne.trimRight();
      if (fin == "}," || fin == "}" || fin == "};") {
        courante = null;
        continue;
      }
      final cle = uneCle.firstMatch(ligne);
      if (cle != null) parLangue[courante]!.add(cle.group(1)!);
    }

    expect(parLangue.keys.length, 9,
        reason: "9 blocs de langue attendus, trouvés : ${parLangue.keys}");

    // Le français fait référence : c'est la langue de repli de `get`, donc la
    // seule dont l'absence d'une clé se verrait tout de suite.
    final reference = parLangue["fr"];
    expect(reference, isNotNull);
    expect(reference!.length, greaterThan(200),
        reason: "analyse du fichier probablement cassée");

    final manques = <String, List<String>>{};
    final surplus = <String, List<String>>{};
    for (final entree in parLangue.entries) {
      if (entree.key == "fr") continue;
      final absentes = reference.difference(entree.value).toList()..sort();
      final enTrop = entree.value.difference(reference).toList()..sort();
      if (absentes.isNotEmpty) manques[entree.key] = absentes;
      if (enTrop.isNotEmpty) surplus[entree.key] = enTrop;
    }

    expect(manques, isEmpty, reason: "clés absentes de certaines langues");
    expect(surplus, isEmpty,
        reason: "clés présentes ailleurs mais pas en français");

    /*
     * 🔴 UN COMPTEUR SANS SA SECONDE FORME ÉCHOUE EN SILENCE.
     *
     * `trN` compose la clé à l'exécution — `<base>_one` ou `<base>_many` selon
     * le nombre. Le compilateur n'en sait rien, et `get` retombe sur le
     * français quand la clé n'existe pas : un `_many` oublié donne un libellé
     * français au milieu d'une interface chinoise, et seulement à partir de
     * DEUX éléments. Personne ne le voit en relisant le code.
     *
     * ⚠️ `_none` reste FACULTATIF, et c'est voulu : les écrans qui distinguent
     * le zéro le traitent avant d'appeler `trN` (voir `colleagues_count_none`).
     * Ne l'exiger que s'il est déjà là aurait interdit les compteurs qui n'en
     * ont pas besoin.
     */
    final orphelines = <String>[];
    for (final cle in reference) {
      if (cle.endsWith("_one") &&
          !reference.contains("${cle.substring(0, cle.length - 4)}_many")) {
        orphelines.add("$cle (pas de _many)");
      }
      if (cle.endsWith("_many") &&
          !reference.contains("${cle.substring(0, cle.length - 5)}_one")) {
        orphelines.add("$cle (pas de _one)");
      }
    }
    orphelines.sort();
    expect(orphelines, isEmpty,
        reason: "compteurs `trN` auxquels il manque une forme");
  });
}
