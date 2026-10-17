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

  group("le genre d'une sonnerie livree", () {
    test("chaque entree en porte un, et les deux familles sont peuplees", () {
      final appels = sonneriesLivreesPour(GenreSonnerie.appel);
      final messages = sonneriesLivreesPour(GenreSonnerie.message);
      // Rien ne se perd entre les deux : le total doit retomber sur le
      // catalogue entier, sinon une entree serait devenue inatteignable.
      expect(appels.length + messages.length, sonneriesLivrees.length);
      expect(appels, isNotEmpty);
      expect(messages, isNotEmpty);
    });

    test("un son de notification n'est jamais propose comme sonnerie d'appel",
        () {
      // 🔴 C'EST LE DEFAUT RAPPORTE LE 15/09/2026 : le selecteur puisait dans
      // le catalogue ENTIER pour les deux champs. Les fichiers disent le genre
      // sans ambiguite — `notif-*` annonce, `sonnerie-*` sonne.
      final appels =
          sonneriesLivreesPour(GenreSonnerie.appel).map((s) => s.fichier);
      expect(appels.where((f) => f.startsWith("notif-")), isEmpty);

      final messages =
          sonneriesLivreesPour(GenreSonnerie.message).map((s) => s.fichier);
      expect(messages.where((f) => f.startsWith("sonnerie-")), isEmpty);
    });

    test("une valeur deja stockee reste lisible quel que soit son genre", () {
      // ⚠️ `assetDeSonnerie` balaie le catalogue ENTIER, volontairement : un
      // choix pose avant ce champ — ou depuis le web — doit rester jouable meme
      // s'il ne serait plus propose aujourd'hui.
      for (final s in sonneriesLivrees) {
        expect(assetDeSonnerie(s.fichier), "sounds/${s.fichier}");
        expect(libelleDeSonnerie(s.fichier), s.libelle);
      }
    });
  });

  group("les canaux de notification Android", () {
    test("chaque son de message a SA RESSOURCE dans res/raw/", () {
      // 🔴 MEME DEFAUT QUE CI-DESSUS, MAIS COTE ANDROID. Un canal cite une
      // ressource par son nom : si le fichier n'est pas dans `res/raw/`, la
      // compilation passe et la notification arrive MUETTE. Et une ressource
      // Android n'accepte ni tiret ni point dans son nom, d'ou la copie de
      // `notif-blip.ogg` en `notif_blip.ogg` — deux exemplaires voulus, le
      // paquet Flutter pour l'application, `res/raw` pour le systeme.
      final manquants = <String>[];
      for (final s in sonneriesLivrees) {
        final res = ressourceAndroidDuSon(s.fichier);
        if (res == null) continue;
        if (!File("android/app/src/main/res/raw/$res.ogg").existsSync()) {
          manquants.add("$res.ogg");
        }
      }
      expect(manquants, isEmpty,
          reason: "canaux sans ressource — notifications muettes : $manquants");
    });

    test("un son inconnu ou importe retombe sur le canal historique", () {
      // ⚠️ LE REPLI EST OBLIGATOIRE : un `channelId` que le telephone ne
      // connait pas et Android 8+ n'affiche RIEN DU TOUT. Mieux vaut le son
      // historique qu'une notification invisible.
      expect(canalMessagePour(null), canalMessageParDefaut);
      expect(canalMessagePour(""), canalMessageParDefaut);
      expect(canalMessagePour("/api/media/abc"), canalMessageParDefaut);
      expect(canalMessagePour("inexistant.ogg"), canalMessageParDefaut);
      // Une SONNERIE D'APPEL n'a pas de canal de message : lui en donner un
      // fabriquerait un identifiant que l'application ne cree jamais.
      expect(canalMessagePour("sonnerie-3.ogg"), canalMessageParDefaut);
    });

    test("« Notification Alanya » reste sur le canal historique", () {
      // Un canal dedie aurait joue exactement le meme son sous un second nom,
      // et fait repartir a zero les reglages qu'Android garde par canal.
      expect(canalMessagePour("notification.mp3"), canalMessageParDefaut);
    });

    test("deux sons de message ne partagent jamais un canal", () {
      final canaux = <String>{};
      final doublons = <String>[];
      for (final s in sonneriesLivrees) {
        if (ressourceAndroidDuSon(s.fichier) == null) continue;
        final c = canalMessagePour(s.fichier);
        if (!canaux.add(c)) doublons.add(c);
      }
      expect(doublons, isEmpty, reason: "canaux en double : $doublons");
      // Les dix sons courts du catalogue, et eux seuls.
      expect(canaux, hasLength(10));
    });
  });
}
