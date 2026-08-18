import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/features/calls/call_controller.dart';
import 'package:alanya/features/calls/widgets/ivr_panel.dart';

/// Spécification exécutable de LA règle du pavé du standard :
/// **il ne change jamais de taille pendant un appel.**
///
/// Pourquoi ce fichier existe. La règle s'est cassée DEUX FOIS, et jamais dans
/// le pavé lui-même : le 17/08/2026 par une bande de message qui apparaissait
/// avec le texte, le 18/08/2026 par un avatar qui grandissait au premier appui
/// sur une touche. Le pavé est le seul `Expanded` de sa colonne — il prend « ce
/// qui reste » — donc **tout ce qui varie au-dessus de lui se prend sur lui**.
/// Une relecture n'attrape pas ça ; il faut mesurer.
///
/// Lancer avec : flutter test test/ivr_panel_hauteur_test.dart
void main() {
  IvrSession session({required bool vocal}) => IvrSession(
        callId: "c1",
        centerId: "u1",
        centerName: "Serveur vocal orange Telecom",
        centerNumber: "303030",
        vocal: vocal,
        options: const [
          IvrOption(digit: 0, label: "Serveur vocal", disponible: true),
          IvrOption(digit: 1, label: "Serveur vocal", disponible: true),
          IvrOption(digit: 2, label: "Serveur vocal", disponible: true),
          IvrOption(digit: 3, label: "Serveur vocal", disponible: true),
        ],
      );

  /// Pose le panneau dans une hauteur FIXE, comme le fait l'écran d'appel, et
  /// rend la taille du pavé.
  Future<Size> mesure(WidgetTester tester, IvrSession s,
      {double hauteur = 600}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: hauteur,
          child: Column(
            children: [
              Expanded(
                child: IvrPanel(
                  session: s,
                  onTouche: (_) async {},
                  onRetourAccueil: () async {},
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    return tester.getSize(find.byKey(IvrPanel.cleDuPave));
  }

  group("afficheLePave — la question que l'écran d'appel pose au panneau", () {
    // C'est ce prédicat qui décide de la taille de l'AVATAR dans
    // `active_call_screen.dart`. Tant que l'écran répondait lui-même en testant
    // `etape == menu`, l'avatar repassait de 64 à 104 points dès qu'un son se
    // jouait, et le pavé perdait la différence. La règle vit désormais ici.
    test("au menu : le pavé est affiché", () {
      final s = session(vocal: true)..etape = IvrEtape.menu;
      expect(IvrPanel.afficheLePave(s), isTrue);
    });
    test(
        "en LECTURE : le pavé est toujours affiché — c'est le cas qui manquait",
        () {
      final s = session(vocal: true)..etape = IvrEtape.lecture;
      expect(IvrPanel.afficheLePave(s), isTrue);
    });
    test("en attente : le pavé cède la place au rond de progression", () {
      final s = session(vocal: false)..etape = IvrEtape.attente;
      expect(IvrPanel.afficheLePave(s), isFalse);
    });
  });

  group("Centre VOCAL — le pavé garde sa taille quand un son se joue", () {
    testWidgets("menu et lecture donnent EXACTEMENT la même hauteur",
        (tester) async {
      final s = session(vocal: true);

      final auMenu = await mesure(tester, s);

      // Le geste qui déclenchait le défaut : l'appelant tape une touche.
      s.etape = IvrEtape.lecture;
      s.toucheEnLecture = 1;
      s.titreEnLecture = "Information sur les produits";
      final enLecture = await mesure(tester, s);

      expect(enLecture.height, auMenu.height,
          reason: "le pavé a changé de hauteur entre le menu et la lecture");
      expect(enLecture.width, auMenu.width);
    });

    testWidgets("un message d'erreur ne reprend rien au pavé", (tester) async {
      final s = session(vocal: true);
      final avant = await mesure(tester, s);

      // Touche invalide : le serveur renvoie un message, l'étape ne bouge pas.
      s.message = "Ce choix ne correspond à aucune option.";
      final apres = await mesure(tester, s);

      expect(apres.height, avant.height);
    });
  });

  group("Rien ne se superpose, même à l'étroit", () {
    // « Que rien ne soit superposé » — demande du user, 18/08/2026.
    //
    // Un débordement de mise en page fait lever une exception à Flutter, que le
    // harnais de test transforme en échec : il suffit donc de rendre le panneau
    // dans des hauteurs de plus en plus courtes pour que le moindre
    // chevauchement se signale. C'est aussi ce qui protège le bandeau de
    // lecture, dont le contenu — icône, titre, bouton — doit tenir dans ses 40
    // points quel que soit le réglage de taille de police du téléphone.
    for (final hauteur in [600.0, 460.0, 380.0, 320.0]) {
      testWidgets("lecture d'un centre vocal dans ${hauteur.toInt()} points",
          (tester) async {
        final s = session(vocal: true)
          ..etape = IvrEtape.lecture
          ..toucheEnLecture = 3
          // Un titre volontairement trop long : il vient de la plateforme du
          // collègue, aucune longueur n'est garantie. Il doit être coupé, pas
          // déborder sur le pavé.
          ..titreEnLecture =
              "Information très détaillée sur l'ensemble de nos produits et services";
        await mesure(tester, s, hauteur: hauteur);
        expect(tester.takeException(), isNull,
            reason: "débordement de mise en page à $hauteur points");
      });
    }
  });

  group("Centre d'APPELS — le bandeau de lecture ne lui coûte rien", () {
    testWidgets("son pavé est PLUS HAUT que celui d'un centre vocal",
        (tester) async {
      // Le bandeau « lecture en cours » est réservé pour un centre vocal et
      // pour lui seul. L'avoir réserve pour tout le monde retirait 40 points
      // aux touches d'un standard qui ne peut jamais l'afficher — exactement la
      // hauteur que le user avait fait ajuster au point près le 17/08/2026.
      final centreAppels = await mesure(tester, session(vocal: false));
      final centreVocal = await mesure(tester, session(vocal: true));

      expect(centreAppels.height, greaterThan(centreVocal.height),
          reason: "le centre d'appels paie un bandeau qu'il n'affiche jamais");
      expect(centreAppels.height - centreVocal.height, 40);
    });

    testWidgets("sa taille ne bouge pas non plus quand un message arrive",
        (tester) async {
      final s = session(vocal: false);
      final avant = await mesure(tester, s);
      s.message = "Assistance technique n'a pas répondu.";
      final apres = await mesure(tester, s);
      expect(apres.height, avant.height);
    });
  });
}
