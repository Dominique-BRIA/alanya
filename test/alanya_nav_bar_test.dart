import 'package:alanya/widgets/alanya_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La barre du bas « plane » (20/11/2026) : fond translucide et flouté. Ce
/// test vérifie qu'elle se construit avec son flou, montre ses onglets et sa
/// pastille, et prévient du bon onglet au toucher.
void main() {
  Widget banc({required ValueChanged<int> onTap, ThemeData? theme}) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        extendBody: true,
        body: ListView(children: List.generate(30, (i) => ListTile(title: Text('Ligne $i')))),
        bottomNavigationBar: AlanyaNavBar(
          currentIndex: 0,
          onTap: onTap,
          items: const [
            AlanyaNavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Discussions'),
            AlanyaNavItem(icon: Icons.call_outlined, activeIcon: Icons.call, label: 'Appels', badge: 3),
          ],
        ),
      ),
    );
  }

  testWidgets('la barre plane : flou, onglets, pastille et toucher', (tester) async {
    int? touche;
    await tester.pumpWidget(banc(onTap: (i) => touche = i));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('Discussions'), findsOneWidget);
    expect(find.text('Appels'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Appels'));
    expect(touche, 1);
  });

  testWidgets('la barre se construit aussi en thème sombre', (tester) async {
    await tester.pumpWidget(banc(onTap: (_) {}, theme: ThemeData.dark()));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
