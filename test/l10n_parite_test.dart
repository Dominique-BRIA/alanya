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
      if (ligne.trimRight() == "},") {
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
  });
}
