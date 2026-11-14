import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/features/status/screens/rognage_image_screen.dart';

/// ROGNER ET FAIRE PIVOTER (14/11/2026) : les dimensions et l'orientation de
/// l'image rendue. Une image de 40 × 20, moitié gauche rouge, moitié droite
/// bleue.
Future<Uint8List> _image() async {
  final r = ui.PictureRecorder();
  final c = Canvas(r);
  c.drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = const Color(0xFFFF0000));
  c.drawRect(const Rect.fromLTWH(20, 0, 20, 20), Paint()..color = const Color(0xFF0000FF));
  final img = await r.endRecording().toImage(40, 20);
  final d = await img.toByteData(format: ui.ImageByteFormat.png);
  return d!.buffer.asUint8List();
}

/// Taille et couleur du pixel (x, y) de [png].
Future<(int, int, Color)> _lire(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final img = (await codec.getNextFrame()).image;
  final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * img.width + x) * 4;
  return (
    img.width,
    img.height,
    Color.fromARGB(px.getUint8(i + 3), px.getUint8(i), px.getUint8(i + 1), px.getUint8(i + 2)),
  );
}

void main() {
  late LocaleController langue;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    langue = LocaleController();
  });

  Future<Uint8List?> ouvrirPuis(WidgetTester tester, Uint8List source,
      Future<void> Function() gestes) async {
    Uint8List? resultat;
    await tester.pumpWidget(ChangeNotifierProvider<LocaleController>.value(
      value: langue,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => resultat = await RognageImageScreen.ouvrir(ctx, source),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    // Le décodage et le calcul passent par le moteur, hors de l'horloge
    // simulée ; et l'indicateur de chargement tourne sans fin, d'où une
    // boucle sur une condition plutôt que `pumpAndSettle`.
    Future<void> attendre(bool Function() fini) async {
      for (var i = 0; i < 50 && !fini(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await attendre(() => find.byType(RawImage).evaluate().isNotEmpty);
    // La fin de l'animation d'ouverture : avant, l'écran est encore agrandi
    // et les boutons ne sont pas à leur place.
    await tester.pump(const Duration(seconds: 1));
    await gestes();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await attendre(() => resultat != null);
    return resultat;
  }

  testWidgets('sans rien toucher : la même image, mêmes dimensions', (tester) async {
    final source = (await tester.runAsync(_image))!;
    final r = await ouvrirPuis(tester, source, () async {});
    expect(r, isNotNull);
    final (w, h, gauche) = (await tester.runAsync(() => _lire(r!, 2, 10)))!;
    expect((w, h), (40, 20));
    expect(gauche, const Color(0xFFFF0000));
  });

  testWidgets("un quart de tour à gauche : 20 × 40, le rouge passe en bas", (tester) async {
    final source = (await tester.runAsync(_image))!;
    final r = await ouvrirPuis(tester, source, () async {
      await tester.tap(find.byIcon(Icons.rotate_90_degrees_ccw));
      await tester.pump();
    });
    final (w, h, bas) = (await tester.runAsync(() => _lire(r!, 10, 38)))!;
    expect((w, h), (20, 40));
    expect(bas, const Color(0xFFFF0000));
    final (_, _, haut) = (await tester.runAsync(() => _lire(r!, 10, 2)))!;
    expect(haut, const Color(0xFF0000FF));
  });

  testWidgets('format carré : 20 × 20, centré', (tester) async {
    final source = (await tester.runAsync(_image))!;
    final r = await ouvrirPuis(tester, source, () async {
      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pump();
    });
    final (w, h, _) = (await tester.runAsync(() => _lire(r!, 0, 0)))!;
    expect((w, h), (20, 20));
  });
}
