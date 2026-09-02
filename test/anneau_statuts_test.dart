import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

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

  group('horodatageStatut', () {
    final maintenant = DateTime.now();

    test('moins d\'une minute', () {
      expect(
        horodatageStatut(maintenant.subtract(const Duration(seconds: 20))),
        "à l'instant",
      );
    });

    test('minutes', () {
      expect(
        horodatageStatut(maintenant.subtract(const Duration(minutes: 12))),
        'il y a 12 min',
      );
      expect(
        horodatageStatut(maintenant.subtract(const Duration(minutes: 59))),
        'il y a 59 min',
      );
    });

    test('heures', () {
      expect(
        horodatageStatut(maintenant.subtract(const Duration(minutes: 60))),
        'il y a 1 h',
      );
      expect(
        horodatageStatut(maintenant.subtract(const Duration(hours: 23))),
        'il y a 23 h',
      );
    });

    test('au-delà de la durée de vie d\'un statut', () {
      expect(
        horodatageStatut(maintenant.subtract(const Duration(hours: 25))),
        'il y a 1 j',
      );
    });

    test(
      'un horodatage UTC est compris comme un instant, pas comme une heure',
      () {
        // `createdAt` arrive du serveur en UTC (`DateTime.parse` d'un « …Z »).
        // La différence de deux instants ne dépend pas du fuseau : sans cette
        // propriété, l'écart afficherait le décalage horaire du téléphone.
        final ilYaDixMinutes = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
        expect(horodatageStatut(ilYaDixMinutes), 'il y a 10 min');
      },
    );
  });
}
