import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/features/status/gestes_visionneuse.dart';
import 'package:alanya/features/status/horodatage_statut.dart';
import 'package:alanya/features/status/widgets/anneau_statuts.dart';

/// Géométrie de l'anneau segmenté et horodatage des statuts.
///
/// Ces deux briques sont pures : elles se vérifient sans écran, ce qui est
/// justement pourquoi elles ont été sorties des widgets.
void main() {
  group('segmentsAnneau', () {
    test('aucun statut ne dessine rien', () {
      expect(segmentsAnneau(0), isEmpty);
      expect(segmentsAnneau(-3), isEmpty);
    });

    test('un seul statut donne un cercle entier, sans entaille', () {
      final s = segmentsAnneau(1);
      expect(s, hasLength(1));
      expect(s.first.balayage, closeTo(2 * math.pi, 1e-12));
      // Départ en haut du cercle.
      expect(s.first.debut, closeTo(-math.pi / 2, 1e-12));
    });

    test('les arcs partent du haut et sont régulièrement espacés', () {
      const n = 5;
      final s = segmentsAnneau(n);
      const pas = 2 * math.pi / n;
      for (var i = 1; i < n; i++) {
        expect(s[i].debut - s[i - 1].debut, closeTo(pas, 1e-12));
      }
      // Le premier arc commence juste après le haut du cercle : il en est
      // décalé d'un demi-écart, pour que l'entaille soit centrée sur le haut.
      final ecart = pas - s.first.balayage;
      expect(s.first.debut, closeTo(-math.pi / 2 + ecart / 2, 1e-12));
    });

    test('arcs et écarts couvrent exactement le tour du cercle', () {
      for (final n in [2, 3, 7, 12]) {
        final s = segmentsAnneau(n);
        expect(s, hasLength(n));
        final pas = 2 * math.pi / n;
        final ecart = pas - s.first.balayage;
        expect(
          s.length * (s.first.balayage + ecart),
          closeTo(2 * math.pi, 1e-9),
          reason: 'n = $n',
        );
      }
    });

    test("l'écart rétrécit, donc un arc reste visible même à 60 statuts", () {
      // C'est LA propriété qui compte : à écart fixe, l'anneau se serait vidé
      // au-delà d'une cinquantaine de statuts.
      for (var n = 2; n <= 60; n++) {
        final s = segmentsAnneau(n);
        expect(s.every((e) => e.balayage > 0), isTrue, reason: 'n = $n');
        // Le trait occupe toujours au moins les deux tiers de son pas.
        final pas = 2 * math.pi / n;
        expect(
          s.first.balayage,
          greaterThanOrEqualTo(pas * 2 / 3 - 1e-12),
          reason: 'n = $n',
        );
      }
    });

    test(
      "l'écart plafonne à sa valeur maximale quand les arcs sont larges",
      () {
        // À 3 statuts, le tiers du pas (0,698) dépasse le plafond : c'est le
        // plafond qui s'applique.
        final s = segmentsAnneau(3);
        final ecart = 2 * math.pi / 3 - s.first.balayage;
        expect(ecart, closeTo(0.12, 1e-12));
      },
    );
  });

  group('gestes de la visionneuse', () {
    test('un appui bref est un tap : il change de statut', () {
      expect(estAppuiCourt(const Duration(milliseconds: 40)), isTrue);
      expect(estAppuiCourt(const Duration(milliseconds: 249)), isTrue);
    });

    test('un maintien n\'est pas un tap : relâcher ne doit rien avancer', () {
      expect(estAppuiCourt(const Duration(milliseconds: 250)), isFalse);
      expect(estAppuiCourt(const Duration(seconds: 3)), isFalse);
    });

    test('le tiers gauche revient en arrière, le reste avance', () {
      const largeur = 360.0;
      expect(zonePrecedente(0, largeur), isTrue);
      expect(zonePrecedente(119, largeur), isTrue);
      expect(zonePrecedente(120, largeur), isFalse);
      expect(zonePrecedente(359, largeur), isFalse);
    });

    test('une largeur nulle ne fait jamais reculer', () {
      // Peut arriver à la toute première image, avant mesure : mieux vaut
      // avancer que rejouer indéfiniment le premier statut.
      expect(zonePrecedente(0, 0), isFalse);
    });
  });

  group('horodatageStatut', () {
    // 🔴 CETTE FONCTION PREND UN `BuildContext` DEPUIS LE LOT i18n : son texte
    // sort desormais du catalogue (`tr`), il n'est plus ecrit en dur. Les
    // attentes restent les memes — le catalogue rend le FRANCAIS par defaut —
    // mais il faut un arbre pour que `AppLocalizations.of` trouve la langue.
    final maintenant = DateTime.now();
    late LocaleController langue;

    setUp(() {
      // `LocaleController` ecrit dans les preferences : sans ce bouchon, il
      // leve faute de canal natif sous `flutter test`.
      SharedPreferences.setMockInitialValues({});
      langue = LocaleController();
    });

    /// Le texte rendu pour [creeLe], mesure dans un arbre qui sait traduire.
    ///
    /// 🔴 L'APPEL SE FAIT PENDANT LE BUILD, ET C'EST OBLIGATOIRE.
    /// `AppLocalizations.of` passe par `context.watch<LocaleController>()`, que
    /// provider REFUSE hors de l'arbre : capturer un contexte pour s'en servir
    /// apres le `pump` leve « Tried to listen to a value exposed with provider,
    /// from outside of the widget tree ». C'est le piege de ce petit harnais.
    Future<String> rendu(WidgetTester tester, DateTime creeLe) async {
      late String texte;
      await tester.pumpWidget(
        ChangeNotifierProvider<LocaleController>.value(
          value: langue,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                texte = horodatageStatut(creeLe, ctx);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return texte;
    }

    testWidgets("moins d'une minute", (tester) async {
      expect(
        await rendu(tester, maintenant.subtract(const Duration(seconds: 20))),
        "à l'instant",
      );
    });

    testWidgets('minutes', (tester) async {
      expect(
        await rendu(tester, maintenant.subtract(const Duration(minutes: 12))),
        'il y a 12 min',
      );
      expect(
        await rendu(tester, maintenant.subtract(const Duration(minutes: 59))),
        'il y a 59 min',
      );
    });

    testWidgets('heures', (tester) async {
      expect(
        await rendu(tester, maintenant.subtract(const Duration(minutes: 60))),
        'il y a 1 h',
      );
      expect(
        await rendu(tester, maintenant.subtract(const Duration(hours: 23))),
        'il y a 23 h',
      );
    });

    testWidgets("au-dela de la duree de vie d'un statut", (tester) async {
      expect(
        await rendu(tester, maintenant.subtract(const Duration(hours: 25))),
        'il y a 1 j',
      );
    });

    testWidgets(
      'un horodatage UTC est compris comme un instant, pas comme une heure',
      (tester) async {
        // `createdAt` arrive du serveur en UTC (`DateTime.parse` d'un « …Z »).
        // La difference de deux instants ne depend pas du fuseau : sans cette
        // propriete, l'ecart afficherait le decalage horaire du telephone.
        final ilYaDixMinutes = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
        expect(await rendu(tester, ilYaDixMinutes), 'il y a 10 min');
      },
    );
  });
}
