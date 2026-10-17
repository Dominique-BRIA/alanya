import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/widgets/media/avancement_compression.dart';

/// « Compression… 42 % » sur le bouton d'envoi pendant qu'une vidéo se
/// transcode (demande du user, 10/10/2026 : « comme sur le web »).
///
/// Lancer avec : flutter test test/avancement_compression_test.dart
void main() {
  late LocaleController langue;

  setUp(() {
    // `LocaleController` écrit dans les préférences : sans ce bouchon, il lève
    // faute de canal natif sous `flutter test`. Même harnais que
    // `anneau_statuts_test.dart` — le catalogue rend le français par défaut.
    SharedPreferences.setMockInitialValues({});
    langue = LocaleController();
  });

  Future<void> monte(WidgetTester tester, Widget enfant) => tester.pumpWidget(
        ChangeNotifierProvider<LocaleController>.value(
          value: langue,
          child: MaterialApp(home: Scaffold(body: Center(child: enfant))),
        ),
      );

  testWidgets("une vidéo : le pourcentage seul", (tester) async {
    await monte(tester, const AvancementCompression(avancement: 0.42));
    await tester.pumpAndSettle();
    expect(find.text('Compression… 42 %'), findsOneWidget);
  });

  testWidgets("plusieurs vidéos : on dit laquelle", (tester) async {
    await monte(tester, const AvancementCompression(avancement: 0.07, rang: 2, total: 3));
    await tester.pumpAndSettle();
    expect(find.text('Vidéo 2/3 · 7 %'), findsOneWidget);
  });

  testWidgets("bornes : jamais moins de 0 ni plus de 100", (tester) async {
    await monte(tester, const AvancementCompression(avancement: 1.3));
    await tester.pumpAndSettle();
    expect(find.text('Compression… 100 %'), findsOneWidget);
  });
}
