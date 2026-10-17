// LE BANDEAU « LA CLÉ DE SÉCURITÉ A CHANGÉ » SE FERME, OÙ QU'ON SOIT.
//
// 🐛 Signalé le 29/09/2026 (capture) : le bandeau restait sur l'ACCUEIL et ses
// deux boutons ne faisaient rien. Il est posé sur le messager de TOUTE
// l'application, donc survit à la sortie de la conversation ; ses boutons
// cherchaient ce messager à partir de l'écran de conversation, déjà détruit —
// et échouaient. Chaque ouverture en ajoutait un de plus, en file.

import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/widgets/e2ee/e2ee_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un écran « conversation » qui affiche le bandeau à son ouverture.
class _Conversation extends StatefulWidget {
  const _Conversation({required this.onIgnorer});
  final VoidCallback onIgnorer;
  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      montrerAvertissementCle(context,
          nomPair: 'Bob', onVerifier: () {}, onIgnorer: widget.onIgnorer);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('fil'));
}

Future<void> _ouvrir(WidgetTester tester, NavigatorState nav, VoidCallback onIgnorer) async {
  nav.push(MaterialPageRoute(builder: (_) => _Conversation(onIgnorer: onIgnorer)));
  await tester.pumpAndSettle();
}

void main() {
  late NavigatorState nav;
  late LocaleController langue;

  // Les textes du bandeau passent par `tr()`, qui lit la langue dans l'arbre ;
  // `LocaleController` écrit dans les préférences, d'où le bouchon.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    langue = LocaleController();
  });

  Widget appli() => ChangeNotifierProvider<LocaleController>.value(
        value: langue,
        child: MaterialApp(
          home: Builder(builder: (c) {
            nav = Navigator.of(c);
            return const Scaffold(body: Text('accueil'));
          }),
        ),
      );

  testWidgets('« Plus tard » ferme le bandeau après être revenu à l’accueil', (tester) async {
    var ignores = 0;
    await tester.pumpWidget(appli());
    await _ouvrir(tester, nav, () => ignores++);
    nav.pop();
    await tester.pumpAndSettle();

    expect(find.text('Plus tard'), findsOneWidget,
        reason: 'témoin : le bandeau est bien resté sur l’accueil');
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'le bouton plantait');
    expect(find.text('Plus tard'), findsNothing, reason: 'le bandeau restait affiché');
    expect(ignores, 1, reason: 'l’alerte n’était pas effacée : elle revenait');
  });

  testWidgets('rouvrir la conversation n’empile pas un second bandeau', (tester) async {
    await tester.pumpWidget(appli());
    await _ouvrir(tester, nav, () {});
    nav.pop();
    await tester.pumpAndSettle();
    await _ouvrir(tester, nav, () {});

    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(find.text('Plus tard'), findsNothing,
        reason: 'un second bandeau attendait en file derrière le premier');
  });
}
