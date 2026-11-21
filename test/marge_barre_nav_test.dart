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
}
