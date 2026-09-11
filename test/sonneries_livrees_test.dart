import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/sonneries_livrees.dart';

/// Spécification exécutable d'UNE règle : **toute sonnerie proposée au choix
/// existe vraiment dans `assets/sounds/`.**
///
/// 🔴 CE CONTRÔLE EXISTE PARCE QUE LE DÉFAUT A EU LIEU. Le 08/09/2026, le
/// catalogue a gagné dix-huit entrées `.ogg` dont les fichiers n'ont jamais été
/// ajoutés au dépôt. Rien ne l'a signalé : `pubspec.yaml` déclare le DOSSIER
/// `assets/sounds/` et non chaque fichier, le dossier existait déjà avec ses
/// `.mp3`, la compilation a donc réussi et l'APK est parti avec dix-huit
/// sonneries qui ne jouaient rien.
///
/// ⚠️ IL LIT LE DISQUE, ET C'EST LE POINT. Sur le poste de développement les
/// fichiers sont là et ce test passe ; c'est la CI, qui part d'un `git clone`
/// propre, qui l'échoue — exactement là où le défaut devenait invisible. Un
/// contrôle qui ne lirait que le tableau ne verrait jamais rien.
///
/// Lancer avec : flutter test test/sonneries_livrees_test.dart
void main() {
  test("chaque sonnerie du catalogue a son fichier dans assets/sounds/", () {
    final dossier = Directory("assets/sounds");
    expect(dossier.existsSync(), isTrue,
        reason: "le test doit tourner depuis la racine du paquet");

    final manquants = <String>[
      for (final s in sonneriesLivrees)
        if (!File("assets/sounds/${s.fichier}").existsSync()) s.fichier,
    ];

    expect(manquants, isEmpty,
        reason: "proposées au choix mais absentes du dépôt — l'utilisateur "
            "les sélectionnerait pour n'entendre aucun son : $manquants");
  });

  test("deux entrées ne partagent pas le même nom de fichier", () {
    // Le nom de fichier est ce qui est STOCKÉ EN BASE : un doublon rendrait le
    // libellé affiché dépendant de l'ordre du tableau.
    final vus = <String>{};
    final doublons = <String>[
      for (final s in sonneriesLivrees)
        if (!vus.add(s.fichier)) s.fichier,
    ];
    expect(doublons, isEmpty, reason: "noms de fichiers en double : $doublons");
  });
}
