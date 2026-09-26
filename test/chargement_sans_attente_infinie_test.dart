import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spécification exécutable de DEUX CONTRÔLES QUE RIEN D'AUTRE NE VOIT.
///
/// 🔴 `dart analyze` NE VOIT NI L'UN NI L'AUTRE, et c'est tout le problème :
///
///   • écrire cinquante pré-clés UNE PAR UNE dans le coffre sécurisé est un code
///     parfaitement légitime — le compilateur n'y reproche rien. Ce que ça
///     casse, c'est le canal de plateforme de toute l'application, sériel : les
///     lectures de coffre qui font la queue derrière, dont celle du jeton de
///     session, ne reviennent plus.
///
///   • un `await` sans borne est légitime aussi. Il ne se remarque qu'au jour où
///     ce qu'il attend ne répond pas — sur le téléphone d'un user, sans journal
///     et sans bouton à toucher.
///
/// Le défaut signalé le 26/09/2026 — « lorsque j'ouvre une conversation, le
/// chargement est infini » — EST LA RENCONTRE DES DEUX : la publication des clés
/// inondait le coffre à chaque démarrage, et l'écran attendait ce même coffre
/// sans délai. La première correction avait bien ajouté l'écriture groupée
/// `storePreKeys`… sans jamais l'appeler : la boucle était restée en place, et
/// rien ne le disait.
///
/// ⚠️ CES CONTRÔLES LISENT LE CODE SOURCE, comme `l10n_parite_test.dart` et
/// `sonneries_livrees_test.dart`. C'est voulu : la règle porte sur la
/// FORME d'un chemin d'exécution — « cette attente est bornée » — et la forme
/// ne s'évalue nulle part ailleurs. Le jour où un `await` nu réapparaîtra dans
/// `_load()`, il passera l'analyse, le build, la revue, et le téléphone de
/// l'utilisateur.
///
/// Lancer avec : flutter test test/chargement_sans_attente_infinie_test.dart
void main() {
  /// Le corps d'une méthode : de son amorce jusqu'à l'accolade qui la ferme.
  ///
  /// ⚠️ La première accolade trouvée EN COLONNE 2 est bien celle de la méthode :
  /// tout ce que contient un corps ferme plus profond (`    }`, `      });`).
  /// S'ancrer sur la section suivante — un commentaire `/* ═══ … ═══ */` — lierait
  /// le test à un dessin, et non à une structure.
  String corps(String chemin, String amorce) {
    final fichier = File(chemin);
    expect(fichier.existsSync(), isTrue,
        reason: "le test doit tourner depuis la racine du paquet");
    final source = fichier.readAsStringSync();
    final debut = source.indexOf(amorce);
    expect(debut, greaterThanOrEqualTo(0),
        reason: "`$amorce` n'existe plus dans $chemin — soit la méthode a été "
            "renommée, soit elle a disparu : dans les deux cas le contrôle "
            "n'a plus rien garanti et il faut le réécrire à la main");
    final fin = source.indexOf("\n  }\n", debut);
    expect(fin, greaterThan(debut), reason: "méthode jamais fermée ?");
    return source.substring(debut, fin);
  }

  test("la publication des pré-clés fait UNE écriture au coffre", () {
    final corpsPublication = corps(
      "lib/services/e2ee/e2ee_service.dart",
      "Future<void> publierMesCles",
    );

    // 🔴 LA RÉGRESSION À CRAINDRE, mot pour mot celle qui a coûté le défaut :
    // `for (final p in uniques) { await coffre.storePreKey(p.id, p); }`.
    // Chaque tour relit et RÉÉCRIT TOUTE la table — cinquante allers-retours
    // d'un contenu qui grossit à chaque tour, soit environ 1 200 entrées
    // re-sérialisées et quatre-vingt-dix traversées du canal, pendant que l'écran de
    // conversation attend son tour.
    expect(
      corpsPublication,
      isNot(contains("coffre.storePreKey(")),
      reason: "une pré-clé à la fois immobilise le coffre pour toute "
          "l'application : c'est la cause racine du chargement infini",
    );
    expect(
      corpsPublication,
      contains("coffre.storePreKeys("),
      reason: "le lot doit partir en UNE écriture — le `s` final est tout le "
          "correctif, et c'est exactement ce que le contrôle vérifie",
    );
  });

  test("toute attente de l'ouverture d'un fil est bornée", () {
    final chargement =
        corps("lib/features/chat/screens/chat_screen.dart", "Future<void> _load()");

    final nonBornes = <String>[];
    for (final instruction in chargement.split(";")) {
      // `unawaited(` ne compte pas : ce qui n'est pas attendu ne peut pas
      // accrocher l'écran — c'est même la réponse à la moitié du défaut.
      if (!instruction.contains("await ")) continue;
      if (instruction.contains(".timeout(")) continue;
      nonBornes.add(instruction.trim().replaceAll(RegExp(r"\s+"), " "));
    }

    expect(nonBornes, isEmpty,
        reason: "une attente sans délai maximal peut ne JAMAIS revenir : le "
            "coffre et la base partagent un canal sériel, et le réseau n'a "
            "aucun délai par défaut. Attendre sans borne, c'est accepter le "
            "chargement infini comme issue possible — $nonBornes");
  });

  test("l'écran n'attend pas le cache pour s'afficher", () {
    // ⚠️ LE CONTRÔLE LE PLUS FACILE À PERDRE : `await MessageCache.putConv(...)`
    // est un réflexe d'écriture parfaitement naturel — et c'est une ÉCRITURE
    // dans la même base, sur le même canal, qui avait rendu le fil infini.
    final chargement =
        corps("lib/features/chat/screens/chat_screen.dart", "Future<void> _load()");

    expect(chargement, isNot(contains("await MessageCache.putConv")),
        reason: "persister vient APRÈS l'affichage, jamais devant : voir "
            "`_reecritLeCache`, qui l'envoie sans l'attendre");
  });
}
