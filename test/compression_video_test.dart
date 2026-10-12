import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/compression_video.dart';

/// LA RÈGLE DE COMPRESSION VIDÉO DU MOBILE EST-ELLE CELLE DU WEB ?
///
/// 🔴 CE QUE CES CAS PROTÈGENT. Le mobile rendait des vidéos deux fois plus
/// lourdes que le web (signalé par le user le 12/10/2026 : 3,9 Mo sur le web
/// contre 8,9 Mo sur le téléphone, pour la même vidéo). La cause n'était pas le
/// transcodeur mais la RÈGLE : débit jamais imposé, grand côté mesuré au lieu
/// du petit, débit de la source ignoré.
///
/// Les valeurs attendues ci-dessous sont celles de `src/lib/video-compression.ts`
/// — le web. Si l'une d'elles change d'un côté sans l'autre, un de ces cas
/// tombe, et c'est tout l'intérêt : l'écart ne peut plus repasser inaperçu.
///
/// ⚠️ ON NE TESTE PAS LE TRANSCODAGE, qui demande un téléphone et un encodeur
/// matériel. On teste la DÉCISION, qui est précisément ce qui doit rester
/// identique aux deux clients.
void main() {
  /// Le poids d'une vidéo de [secondes] à [debit] bits/s.
  int poids(double secondes, int debit) => (secondes * debit / 8).round();

  group('consignePour — ce qu\'on ne touche pas', () {
    test('une vidéo déjà en 720p et déjà légère est laissée intacte', () {
      // 1280 × 720 à 1,8 Mbit/s : exactement ce qui sort de chez nous.
      final c = consignePour(
        largeur: 1280,
        hauteur: 720,
        tailleOctets: poids(30, 1800000),
        dureeMs: 30000,
      );
      expect(c.transcode, isFalse);
      expect(c.raison, RaisonSautVideo.dejaPetite);
    });

    test('une vidéo DE CHEZ NOUS repartagée ne se dégrade pas', () {
      // Le même fichier passé trois fois par le partage doit rester intact à
      // chaque fois — sinon il pâlit à chaque saut.
      for (var saut = 0; saut < 3; saut++) {
        final c = consignePour(
          largeur: 1280,
          hauteur: 720,
          tailleOctets: poids(12, 1800000),
          dureeMs: 12000,
        );
        expect(c.transcode, isFalse, reason: 'saut $saut');
      }
    });

    test('dimensions illisibles : on n\'y touche pas', () {
      final c = consignePour(
          largeur: 0, hauteur: 0, tailleOctets: 5000000, dureeMs: 10000);
      expect(c.raison, RaisonSautVideo.dimensionsInconnues);
    });
  });

  group('consignePour — ce qu\'on réduit', () {
    test('du 1080p devient du 720p à 1,6 Mbit/s', () {
      final c = consignePour(
        largeur: 1920,
        hauteur: 1080,
        tailleOctets: poids(30, 8000000),
        dureeMs: 30000,
      );
      expect(c.transcode, isTrue);
      expect([c.bordLong, c.bordCourt], [1280, 720]);
      expect(c.debit, 1600000);
    });

    test('la 4K aussi, et pas davantage', () {
      final c = consignePour(
        largeur: 3840,
        hauteur: 2160,
        tailleOctets: poids(10, 40000000),
        dureeMs: 10000,
      );
      expect([c.bordLong, c.bordCourt], [1280, 720]);
      expect(c.debit, 1600000);
    });

    test('une vidéo PORTRAIT garde son sens : 720 de large, 1280 de haut', () {
      final c = consignePour(
        largeur: 1080,
        hauteur: 1920,
        tailleOctets: poids(20, 9000000),
        dureeMs: 20000,
      );
      expect(c.bordCourt, 720);
      expect(c.bordLong, 1280);
    });

    test('une vidéo 720p filmée à très haut débit est allégée SANS être réduite',
        () {
      // C'est le cas que le mobile ratait : l'image est déjà bonne, c'est le
      // débit qui est absurde.
      final c = consignePour(
        largeur: 1280,
        hauteur: 720,
        tailleOctets: poids(30, 6000000),
        dureeMs: 30000,
      );
      expect(c.transcode, isTrue);
      expect([c.bordCourt, c.bordLong], [720, 1280]);
      expect(c.debit, 1600000);
    });

    test('une vidéo PLUS PETITE que 720p n\'est jamais agrandie', () {
      final c = consignePour(
        largeur: 640,
        hauteur: 360,
        tailleOctets: poids(10, 5000000),
        dureeMs: 10000,
      );
      expect(c.transcode, isTrue);
      expect([c.bordCourt, c.bordLong], [360, 640],
          reason: 'les dimensions d\'origine sont conservées');
      // Un quart de la surface d'un 720p : un quart du débit, soit le plancher.
      expect(c.debit, debitPlancher);
    });

    test('durée inconnue : on transcode plutôt que de conclure à la légère',
        () {
      final c = consignePour(
          largeur: 1920, hauteur: 1080, tailleOctets: 50000000, dureeMs: 0);
      expect(c.transcode, isTrue);
    });

    test('les dimensions sont toujours paires (exigence du H.264)', () {
      // 1001 × 563 : le facteur donne des nombres impairs avant arrondi.
      final c = consignePour(
        largeur: 1001,
        hauteur: 563,
        tailleOctets: poids(10, 9000000),
        dureeMs: 10000,
      );
      expect(c.bordCourt.isEven, isTrue);
      expect(c.bordLong.isEven, isTrue);
    });
  });

  group('debitPour — la part de chaque surface', () {
    test('un 720p plein reçoit le débit de référence', () {
      expect(debitPour(1280, 720), debit720p);
    });

    test('la moitié de la surface reçoit la moitié du débit', () {
      expect(debitPour(905, 509), closeTo(debit720p / 2, debit720p * 0.01));
    });

    test('une toute petite image ne descend pas sous le plancher', () {
      expect(debitPour(160, 120), debitPlancher);
    });
  });

  group('les nombres sont bien ceux du web', () {
    test('720 de petit côté, 1,6 Mbit/s, 2,5 Mbit/s, 10 % de gain', () {
      expect(videoBordCourtMax, 720, reason: 'VIDEO_BORD_COURT');
      expect(debit720p, 1600000, reason: 'DEBIT_720P');
      expect(debitDejaLeger, 2500000, reason: 'DEBIT_DEJA_LEGER');
      expect(gainMinimumVideo, 0.9, reason: 'GAIN_MINIMUM');
    });
  });
}
