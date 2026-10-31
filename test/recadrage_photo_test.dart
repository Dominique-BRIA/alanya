import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/features/account/screens/recadrage_photo_screen.dart';
import 'package:alanya/core/locale_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le recadrage de la photo de profil (01/11/2026) : sans geste, il garde le
/// carré du milieu. Lancer avec : flutter test test/recadrage_photo_test.dart
void main() {
  /// Une image de 1000 × 500 : rouge à gauche, bleue à droite.
  Future<Uint8List> imageTest() async {
    final r = ui.PictureRecorder();
    final c = Canvas(r);
    c.drawRect(
      const Rect.fromLTWH(0, 0, 500, 500),
      Paint()..color = const Color(0xFFFF0000),
    );
    c.drawRect(
      const Rect.fromLTWH(500, 0, 500, 500),
      Paint()..color = const Color(0xFF0000FF),
    );
    final img = await r.endRecording().toImage(1000, 500);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  testWidgets('sans geste, le carré du milieu de l\'image', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final entree = (await tester.runAsync(imageTest))!;
    Uint8List? sortie;
    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleController>.value(
        value: LocaleController(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  sortie = await RecadragePhotoScreen.ouvrir(context, entree),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    // Le décodage est une vraie opération asynchrone.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();
    expect(sortie, isNotNull);

    final pixels = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(sortie!);
      final img = (await codec.getNextFrame()).image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (img.width, img.height, data!);
    });
    final (l, h, data) = pixels!;
    // Le carré de 500 du milieu : x de 250 à 750 — sortie de 500 pixels.
    expect(l, 500);
    expect(h, 500);
    Color px(int x, int y) {
      final i = (y * l + x) * 4;
      return Color.fromARGB(
        255,
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    }

    // Moitié gauche rouge, moitié droite bleue.
    expect(px(100, 250).red, greaterThan(200));
    expect(px(400, 250).blue, greaterThan(200));
  });
}
