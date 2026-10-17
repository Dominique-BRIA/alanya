// LE SÉLECTEUR D'EMOJIS : catalogue complet, recherche, récents.
//
// Demande du user (02/10/2026) : « augmenter le nombre d'emojis, mobile comme
// web ». Le chat en proposait 24 ; le catalogue commun en compte 1 812.

import 'package:alanya/core/emojis_catalogue.dart';
import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/widgets/selecteur_emojis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocaleController langue;
  late List<String> choisis;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    langue = LocaleController();
    choisis = [];
  });

  Widget appli() => ChangeNotifierProvider<LocaleController>.value(
        value: langue,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: SelecteurEmojis(onChoisir: choisis.add),
            ),
          ),
        ),
      );

  test('le catalogue commun : 8 catégories, 1 812 emojis, sans doublon', () {
    expect(catalogueEmojis.map((c) => c.id), [
      'smileys', 'nature', 'nourriture', 'activites',
      'voyages', 'objets', 'symboles', 'drapeaux',
    ]);
    final tous = [for (final c in catalogueEmojis) for (final e in c.emojis) e.$1];
    expect(tous.length, 1812);
    expect(tous.toSet().length, tous.length);
  });

  testWidgets('la recherche trouve en français, sans accents', (tester) async {
    await tester.pumpWidget(appli());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cœur rouge');
    await tester.pumpAndSettle();
    expect(find.text('❤️'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'pizza');
    await tester.pumpAndSettle();
    expect(find.text('🍕'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzzqqq');
    await tester.pumpAndSettle();
    expect(find.text('Aucun emoji trouvé'), findsOneWidget);
  });

  testWidgets('un emoji choisi est inséré PUIS retenu dans les récents', (tester) async {
    await tester.pumpWidget(appli());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.access_time), findsNothing,
        reason: 'pas d’onglet « récents » tant que rien n’a été choisi');

    await tester.tap(find.text('😀'));
    await tester.pumpAndSettle();
    expect(choisis, ['😀']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('emojis_recents'), ['😀']);
    expect(find.byIcon(Icons.access_time), findsOneWidget);
  });

  testWidgets('les onglets changent de catégorie', (tester) async {
    await tester.pumpWidget(appli());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    expect(find.text('🏁'), findsOneWidget);
    expect(find.text('😀'), findsNothing);
  });
}
