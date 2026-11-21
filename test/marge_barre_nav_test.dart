import 'package:alanya/widgets/alanya_nav_bar.dart';
import 'package:alanya/widgets/marge_barre_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La barre du bas flotte au-dessus du contenu (extendBody). Le bouton flottant
/// d'un onglet qui a son propre Scaffold (Réunions, Statuts) passait DESSOUS :
/// ce test le montre, puis vérifie que [AuDessusDeLaBarre] le remonte.
void main() {
  Widget accueil({required bool remonte}) {
    const fab = FloatingActionButton(onPressed: null, child: Icon(Icons.add));
    return MaterialApp(
      home: Scaffold(
        extendBody: true,
        // Comme un onglet : le contexte de l'ÉCRAN, au-dessus de son Scaffold.
        body: Builder(
          builder: (ecran) => Scaffold(
            body: ListView(children: List.generate(40, (i) => ListTile(title: Text('Ligne $i')))),
            floatingActionButton:
                remonte ? AuDessusDeLaBarre(marge: margeBasseBarre(ecran), child: fab) : fab,
          ),
        ),
        bottomNavigationBar: AlanyaNavBar(
          currentIndex: 0,
          onTap: (_) {},
          items: const [
            AlanyaNavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Discussions'),
            AlanyaNavItem(icon: Icons.videocam_outlined, activeIcon: Icons.videocam, label: 'Réunions'),
          ],
        ),
      ),
    );
  }

  testWidgets("sans correction, le bouton d'un onglet passe sous la barre", (tester) async {
    await tester.pumpWidget(accueil(remonte: false));
    final bouton = tester.getRect(find.byType(FloatingActionButton));
    final barre = tester.getRect(find.byType(AlanyaNavBar));
    expect(bouton.bottom > barre.top, isTrue);
  });

  testWidgets('AuDessusDeLaBarre remonte le bouton au-dessus de la barre', (tester) async {
    await tester.pumpWidget(accueil(remonte: true));
    final bouton = tester.getRect(find.byType(FloatingActionButton));
    final barre = tester.getRect(find.byType(AlanyaNavBar));
    expect(bouton.bottom <= barre.top, isTrue,
        reason: 'bouton ${bouton.bottom} / barre ${barre.top}');
  });

  // 🐛 21/11/2026 : avec les trois boutons d'Android (retour, accueil,
  // récents), la barre passait dessous. Elle doit rester au-dessus de la zone
  // que le système réserve en bas.
  testWidgets('la barre reste au-dessus des boutons du système', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 48 * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(accueil(remonte: true));
    final ecran = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final barre = tester.getRect(find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 64));
    expect(barre.bottom <= ecran - 48, isTrue,
        reason: 'barre ${barre.bottom} / écran $ecran (48 réservés en bas)');
  });
}
