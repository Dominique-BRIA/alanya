import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/compression_image.dart';

/// Spécification exécutable de la compression des photos avant envoi.
///
/// 🔴 POURQUOI CE TEST (06/10/2026). Les captures d'écran partaient intactes —
/// 400 Ko à 1 Mo chacune — parce que le module refusait TOUT PNG pour en
/// protéger la transparence. Il distingue désormais : une capture opaque
/// devient JPEG, un logo transparent et un PNG animé restent tels quels. Ce
/// tri ne se voit qu'à l'envoi, chez le correspondant : on le vérifie ici.
///
/// Lancer avec : flutter test test/compression_image_test.dart
void main() {
  /// Un PNG de [l] × [h], entièrement opaque ou avec un disque sur du vide.
  Future<Uint8List> png(int l, int h, {required bool transparent}) async {
    final enregistreur = ui.PictureRecorder();
    final toile = ui.Canvas(enregistreur);
    final peinture = ui.Paint()..color = const ui.Color(0xFFC04D29);
    if (transparent) {
      toile.drawCircle(ui.Offset(l / 2, h / 2), l / 3, peinture);
    } else {
      toile.drawRect(
          ui.Rect.fromLTWH(0, 0, l.toDouble(), h.toDouble()), peinture);
    }
    final image = await enregistreur.endRecording().toImage(l, h);
    final donnees = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return donnees!.buffer.asUint8List();
  }

  group("Quels PNG deviennent des JPEG", () {
    testWidgets("une capture d'écran opaque est compressée", (tester) async {
      await tester.runAsync(() async {
        expect(await pngIntouchable(await png(540, 1200, transparent: false)),
            isNull);
      });
    });

    testWidgets("un logo transparent reste un PNG", (tester) async {
      await tester.runAsync(() async {
        expect(await pngIntouchable(await png(400, 400, transparent: true)),
            RaisonSaut.transparente,
            reason: "en JPEG, son fond deviendrait noir");
      });
    });

    testWidgets("un PNG animé reste un PNG", (tester) async {
      await tester.runAsync(() async {
        final fixe = await png(200, 200, transparent: false);
        // Un bloc `acTL` glissé juste après l'IHDR : c'est ce qui fait un APNG.
        final actl = Uint8List.fromList([
          0, 0, 0, 8, 0x61, 0x63, 0x54, 0x4c, //
          0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0,
        ]);
        final anime = Uint8List.fromList(
            [...fixe.sublist(0, 33), ...actl, ...fixe.sublist(33)]);
        expect(await pngIntouchable(anime), RaisonSaut.animee,
            reason: "un canvas n'en garderait que la première image");
      });
    });

    testWidgets("un PNG tronqué n'est pas touché", (tester) async {
      await tester.runAsync(() async {
        final entier = await png(200, 200, transparent: false);
        expect(await pngIntouchable(entier.sublist(0, 40)),
            RaisonSaut.decodageImpossible);
      });
    });
  });

  group("La consigne de taille donne un bord long de 1600 px", () {
    test("Android : le cadre carré vaut le bord court visé", () {
      // Glide remplit le cadre : 1200 × 1200 → 1600 × 1200.
      expect(consigneVignette(4000, 3000, android: true).width, 1200);
      expect(consigneVignette(3000, 4000, android: true).width, 1200);
      // Capture 1080 × 2400 → 720 × 1600, et non 1600 × 3556.
      expect(consigneVignette(1080, 2400, android: true).width, 720);
    });

    test("iOS : le cadre carré vaut le bord long visé", () {
      expect(consigneVignette(4000, 3000, android: false).width, imageBordMax);
    });

    test("une image déjà petite n'est jamais agrandie", () {
      final a = consigneVignette(720, 1280, android: true);
      expect([a.width, a.height], [720, 720]);
      final i = consigneVignette(720, 1280, android: false);
      expect([i.width, i.height], [1280, 1280]);
    });

    test("dimensions inconnues : la borne seule", () {
      final c = consigneVignette(0, 0, android: true);
      expect([c.width, c.height], [imageBordMax, imageBordMax]);
    });
  });
}
