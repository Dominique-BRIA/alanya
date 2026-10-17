import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/compression_image.dart';
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

  /// LE DÉBIT D'UNE DE NOS PROPRES SORTIES EN 720p — image plus son.
  ///
  /// ⚠️ DÉRIVÉ DES CONSTANTES, JAMAIS ÉCRIT EN DUR : ces bancs se sont déjà
  /// périmés une fois pour avoir figé 1,8 Mbit/s dans le code. Si le débit du
  /// palier change, ce nombre suit, et les bancs continuent de poser la bonne
  /// question.
  final int debitDeNotreSortie720p = debitPalier[720]! + 128000;

  group('consignePour — ce qu\'on ne touche pas', () {
    test('une vidéo SORTIE DE CHEZ NOUS n\'est pas redescendue d\'une marche', () {
      // 1280 × 720 au débit de notre palier : exactement ce qui sort de chez
      // nous. Sans le seuil, l'escalier la ferait tomber à 360p.
      final c = consignePour(
        largeur: 1280,
        hauteur: 720,
        tailleOctets: poids(30, debitDeNotreSortie720p),
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
          tailleOctets: poids(12, debitDeNotreSortie720p),
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
    test('du 1080p devient du 720p au débit du palier (une seule marche)', () {
      final c = consignePour(
        largeur: 1920,
        hauteur: 1080,
        tailleOctets: poids(30, 8000000),
        dureeMs: 30000,
      );
      expect(c.transcode, isTrue);
      expect([c.bordLong, c.bordCourt], [1280, 720]);
      expect(c.debit, debitPalier[720]);
    });

    test('la 4K aussi, et pas davantage', () {
      final c = consignePour(
        largeur: 3840,
        hauteur: 2160,
        tailleOctets: poids(10, 40000000),
        dureeMs: 10000,
      );
      expect([c.bordLong, c.bordCourt], [1280, 720]);
      expect(c.debit, debitPalier[720]);
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

    test('une vidéo 720p à très haut débit descend d\'une marche : 360p', () {
      // 6 Mbit/s en 720p : ce n'est pas une de nos sorties, l'escalier joue.
      final c = consignePour(
        largeur: 1280,
        hauteur: 720,
        tailleOctets: poids(30, 6000000),
        dureeMs: 30000,
      );
      expect(c.transcode, isTrue);
      expect([c.bordCourt, c.bordLong], [360, 640]);
      expect(c.debit, debitPalier[360]);
    });

    test('une vidéo PLUS PETITE que 720p n\'est jamais agrandie', () {
      // 360p à 5 Mbit/s : pas une de nos sorties, donc une marche de plus.
      final c = consignePour(
        largeur: 640,
        hauteur: 360,
        tailleOctets: poids(10, 5000000),
        dureeMs: 10000,
      );
      expect(c.transcode, isTrue);
      expect([c.bordCourt, c.bordLong], [240, 426],
          reason: 'jamais agrandie — descendue d\'une marche');
      expect(c.debit, debitPalier[240]);
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

  group('le niveau haut — 720p au plus, ou l\'original intact', () {
    test('du 4K descend à 720p, et pas plus bas (17/10/2026)', () {
      // 🔴 Le plafond du niveau haut est passé de 1080 à 720 : plus aucune
      // vidéo ne sort d'ici au-dessus de 720p.
      final c = consignePour(
        largeur: 3840,
        hauteur: 2160,
        tailleOctets: poids(10, 40000000),
        dureeMs: 10000,
        niveau: NiveauQualite.haute,
      );
      expect([c.bordLong, c.bordCourt], [1280, 720]);
      expect(c.debit, debitHaute720,
          reason: 'c\'est le DÉBIT qui distingue les deux niveaux à 720p : le '
              'normal met 1,2 Mbit/s, le haut 2,5');
    });

    test('une vidéo filmée en 720p PART ENTIÈRE au niveau haut', () {
      /*
       * 🔴 RÈGLE DU USER, 17/10/2026 : « si la vidéo est inférieure à 720 et
       * qu'on clique sur meilleure qualité, alors ça ne compresse plus ». Le
       * bouton ne promet pas mieux que l'original — on n'agrandit jamais — mais
       * mieux que la marche que l'escalier allait prendre.
       */
      final c = consignePour(
        largeur: 1280,
        hauteur: 720,
        tailleOctets: poids(30, 6000000),
        dureeMs: 30000,
        niveau: NiveauQualite.haute,
      );
      expect(c.transcode, isFalse);
      expect(c.raison, RaisonSautVideo.dejaPetite);
      /*
       * 🐛 CE BANC DISAIT L'INVERSE, ET IL AVAIT TORT DEPUIS L'ESCALIER. Au
       * niveau normal, une vidéo filmée en 720p part en 360p : le niveau haut
       * lui rend ses 720p, le bouton a donc tout son sens. C'est le défaut
       * signalé par le professeur le 16/10/2026 — « il n'y a pas le bouton pour
       * envoyer à meilleure qualité comme ça se fait sur les photos ».
       */
      expect(hautePlusFine(720), isTrue,
          reason: 'le niveau normal donne 360p : le bouton rend du 720p entier');
      expect(hautePlusFine(240), isFalse,
          reason: 'sous le plancher, rien à surclasser');
      expect(hautePlusFine(1080), isTrue,
          reason: 'au-dessus de 720 les deux niveaux donnent du 720p, mais pas '
              'au même débit — le bouton reste utile (règle du user, 17/10)');
    });

    test('UNE VIDÉO SOUS 720p N\'EST JAMAIS AGRANDIE PAR LE NIVEAU HAUT', () {
      /*
       * 🔴 LA CRAINTE EXPLICITE DU USER (17/10/2026) : « comme on ne veut pas
       * que ça agrandisse l'image pour envoyer à 720p, on envoie juste la
       * taille originale ». Une 480p lourde part donc ENTIÈRE au niveau haut —
       * ni remontée à 720p, ni descendue à 360p comme le ferait l'escalier.
       */
      for (final taille in [
        [854, 480],
        [640, 360],
        [426, 240],
      ]) {
        final c = consignePour(
          largeur: taille[0],
          hauteur: taille[1],
          tailleOctets: poids(20, 9000000),
          dureeMs: 20000,
          niveau: NiveauQualite.haute,
        );
        expect(c.transcode, isFalse,
            reason: '${taille[0]}x${taille[1]} : rien ne doit être produit');
        expect(c.raison, RaisonSautVideo.dejaPetite);
      }
    });

    test('une vidéo entre 720p et 1080p descend à 720p elle aussi', () {
      final c = consignePour(
        largeur: 1600,
        hauteur: 900,
        tailleOctets: poids(20, 9000000),
        dureeMs: 20000,
        niveau: NiveauQualite.haute,
      );
      expect([c.bordCourt, c.bordLong], [720, 1280]);
      expect(c.debit, debitHaute720);
      expect(hautePlusFine(900), isTrue,
          reason: 'même définition que le normal, mais deux fois le débit : le '
              'bouton a quelque chose à offrir');
    });

    test('rien à gagner : une 1080p légère n\'est pas retranscodée', () {
      // 🔴 LE CAS A CHANGÉ AVEC LE PLAFOND À 720 : à 2 Mbit/s, une 1080p a
      // maintenant quelque chose à gagner (1,2 Mbit/s visé), et elle descend.
      // Il reste une vidéo qui n'a rien à gagner : celle qui est DÉJÀ plus
      // légère que le débit visé. On s'abstient avant de faire tourner
      // l'encodeur, plutôt que de l'alourdir.
      final c = consignePour(
        largeur: 1920,
        hauteur: 1080,
        tailleOctets: poids(30, 1000000),
        dureeMs: 30000,
        niveau: NiveauQualite.haute,
      );
      expect(c.transcode, isFalse);
      expect(c.raison, RaisonSautVideo.dejaPetite);
    });

    test('la même, au niveau normal, est bien réduite en 720p', () {
      final c = consignePour(
        largeur: 1920,
        hauteur: 1080,
        tailleOctets: poids(30, 2000000),
        dureeMs: 30000,
      );
      expect(c.transcode, isTrue);
      expect([c.bordCourt, c.bordLong], [720, 1280]);
    });

    test('le haut est toujours au moins aussi fin que le normal', () {
      for (final taille in [[640, 360], [1280, 720], [1600, 900], [1920, 1080], [3840, 2160]]) {
        final normal = consignePour(
          largeur: taille[0],
          hauteur: taille[1],
          tailleOctets: poids(10, 30000000),
          dureeMs: 10000,
        );
        final haut = consignePour(
          largeur: taille[0],
          hauteur: taille[1],
          tailleOctets: poids(10, 30000000),
          dureeMs: 10000,
          niveau: NiveauQualite.haute,
        );
        /*
         * ⚠️ « NE PAS TRANSCODER » EST LE PLUS FIN DES DEUX, et c'est ce que
         * fait le niveau haut sous 720p : la vidéo part entière. On compare
         * donc la définition QUI SORT, en prenant celle de la source quand
         * rien n'est fait.
         */
        final courtSource = math.min(taille[0], taille[1]);
        final hautCourt = haut.transcode ? haut.bordCourt : courtSource;
        final normalCourt = normal.transcode ? normal.bordCourt : courtSource;
        expect(hautCourt, greaterThanOrEqualTo(normalCourt),
            reason: '${taille[0]}x${taille[1]} : définition');
      }
    });
  });

  group('l\'escalier des paliers (13/10/2026)', () {
    test('on descend d\'UNE marche, jamais plus', () {
      expect(palierVideo(1080), 720);
      expect(palierVideo(721), 720);
      expect(palierVideo(720), 360, reason: '720 exactement : marche suivante');
      expect(palierVideo(480), 360);
      expect(palierVideo(360), 240);
      expect(palierVideo(241), 240);
      expect(palierVideo(240), isNull, reason: 'le plancher');
      expect(palierVideo(144), isNull);
    });

    test('LE SEUIL AU DÉBIT ÉPARGNE CE QUI EST DÉJÀ LÉGER (16/10/2026)', () {
      // La demande du professeur : le débit décide, pas la définition.
      expect(dejaAssezLegere(1000000), isTrue, reason: '1 Mbit/s : on n\'y touche pas');
      expect(dejaAssezLegere(seuilDebit.toDouble()), isTrue, reason: 'le seuil est inclus');
      expect(dejaAssezLegere(seuilDebit + 1), isFalse);
      expect(dejaAssezLegere(6000000), isFalse);
    });

    test('UNE DE NOS SORTIES NE REDÉCLENCHE JAMAIS LA COMPRESSION', () {
      /*
       * 🔴 L'INVARIANT QUI REMPLACE LA GARDE CONTRE LA CASCADE. Elle
       * reconnaissait nos fichiers à leur FORME (petit côté sur un palier,
       * débit sous celui du palier). Elle n'a plus lieu d'être : aucune de nos
       * sorties ne dépasse le seuil. ⚠️ Si ce banc tombe, la cascade est
       * rouverte et une vidéo reperd une marche à chaque partage.
       */
      for (final palier in paliersVideo) {
        expect(debitPalier[palier]! + margeSon, lessThanOrEqualTo(seuilDebit),
            reason: 'palier $palier : notre sortie doit rester sous le seuil');
      }
    });

    test('une vidéo 720p LÉGÈRE reste intacte — le défaut signalé', () {
      // Le cas même du professeur : 720p à 1 Mbit/s. Avant le 16/10, l'escalier
      // la faisait tomber en 360p pour un gain dérisoire.
      final c = consignePour(
        largeur: 1280,
        hauteur: 720,
        tailleOctets: poids(30, 1000000),
        dureeMs: 30000,
      );
      expect(c.transcode, isFalse);
      expect(c.raison, RaisonSautVideo.dejaPetite);
    });

    test('et une 1080p légère aussi : la définition ne décide plus', () {
      final c = consignePour(
        largeur: 1920,
        hauteur: 1080,
        tailleOctets: poids(60, 1200000),
        dureeMs: 60000,
      );
      expect(c.transcode, isFalse,
          reason: 'déjà sous le seuil : la descendre en 720p ne rendrait '
              'presque rien et coûterait des pixels');
    });

    test('UNE VIDÉO NE SE DÉGRADE PAS À CHAQUE PARTAGE', () {
      // Le scénario qui a motivé la garde : on envoie, le correspondant
      // enregistre dans sa galerie et renvoie, trois fois de suite.
      var largeur = 1920;
      var hauteur = 1080;
      var debit = 8000000;
      final tailles = <int>[];
      for (var tour = 0; tour < 4; tour++) {
        final c = consignePour(
          largeur: largeur,
          hauteur: hauteur,
          tailleOctets: poids(30, debit),
          dureeMs: 30000,
        );
        if (!c.transcode) break;
        hauteur = c.bordCourt;
        largeur = c.bordLong;
        // Ce qui sort de chez nous : le débit du palier, plus le son.
        debit = c.debit + 128000;
        tailles.add(c.bordCourt);
      }
      expect(tailles, [720],
          reason: 'une seule réduction : ensuite notre sortie est sous le '
              'seuil, et le seuil ne la touche plus');
    });
  });

  group('l\'étiquette du bouton dit ce qu\'elle va faire', () {
    test('la définition de l\'autre niveau, et non un nombre de principe', () {
      // 🐛 Le bouton annonçait « Envoyer en 1080p » même pour une source qui
      // ne pouvait pas le rendre : on n'agrandit jamais. Et depuis le 17/10, le
      // plafond du niveau haut est 720 : il n'annonce plus jamais 1080p.
      expect(definitionAutreNiveauVideo(720, NiveauQualite.normal), 720,
          reason: 'une vidéo filmée en 720p part entière au niveau haut');
      expect(definitionAutreNiveauVideo(360, NiveauQualite.normal), 360);
      expect(definitionAutreNiveauVideo(1080, NiveauQualite.normal), 720,
          reason: 'le plafond du niveau haut');
      expect(definitionAutreNiveauVideo(4000, NiveauQualite.normal), 720);
      // Depuis le niveau haut, le retour annonce la marche de l'escalier.
      expect(definitionAutreNiveauVideo(720, NiveauQualite.haute), 360);
      expect(definitionAutreNiveauVideo(1080, NiveauQualite.haute), 720);
    });
  });

  group('les nombres sont bien ceux du web', () {
    test('les paliers et leurs débits, à l\'identique', () {
      expect(videoBordCourtMax, 720, reason: 'VIDEO_BORD_COURT');
      expect(seuilDebit, 1450000, reason: 'SEUIL_DEBIT');
      expect(margeSon, 250000, reason: 'MARGE_SON');
      expect(paliersVideo, [720, 360, 240], reason: 'PALIERS_VIDEO');
      expect(debitPalier, {720: 1200000, 360: 600000, 240: 300000},
          reason: 'DEBIT_PALIER');
      expect(paliersImage, [1600, 1000, 640], reason: 'PALIERS_IMAGE');
      expect(gainMinimumVideo, 0.9, reason: 'GAIN_MINIMUM');
      expect(videoBordCourtHaute, 720,
          reason: 'VIDEO_BORD_COURT_HAUTE — plafond ramené de 1080 à 720 le '
              '17/10/2026, et plus aucune vidéo ne sort d\'ici au-dessus');
      expect(imageBordMax, 1600, reason: 'IMAGE_BORD_MAX');
      expect(imageBordMaxHaute, 2560, reason: 'IMAGE_BORD_MAX_HAUTE');
      expect(imageQualite, 82, reason: 'IMAGE_QUALITE (0,82 côté web)');
      expect(imageQualiteHaute, 90, reason: 'IMAGE_QUALITE_HAUTE (0,90)');
    });
  });
}
