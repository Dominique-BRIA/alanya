import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/features/auth/screens/welcome_screen.dart';

void main() {
  // 🔴 LE PROVIDER N'EST PAS UN DÉTAIL DE MONTAGE, c'est ce que le test
  // vérifiait sans le savoir.
  //
  // L'écran passe par `tr(context, …)`, et `AppLocalizations.of` lit la langue
  // courante avec `context.watch<LocaleController>()`. Monté seul, l'écran
  // lève `ProviderNotFoundException` avant d'afficher la moindre ligne — et
  // l'échec se lit « 0 widget trouvé », ce qui ressemble à un libellé disparu
  // alors que c'est l'arbre qui manquait.
  late LocaleController langue;

  Widget monter() => ChangeNotifierProvider<LocaleController>.value(
        value: langue,
        child: const MaterialApp(home: WelcomeScreen()),
      );

  setUp(() {
    // `setLocale` écrit dans les préférences : sans ce bouchon, l'appel lève
    // faute de canal natif sous `flutter test`.
    SharedPreferences.setMockInitialValues({});
    langue = LocaleController();
  });

  testWidgets('en français, la signature et les deux boutons', (tester) async {
    await tester.pumpWidget(monter());

    // ⚠️ Le test attendait « Bienvenue sur Alanya », un libellé QUI N'EXISTE
    // PLUS : l'écran affiche la signature de l'application. L'attente était
    // périmée, pas l'écran — d'où un test rouge qui ne signalait aucun défaut.
    expect(find.text('Discutez, appelez, partagez — en toute simplicité.'),
        findsOneWidget);
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text("J'ai déjà un compte"), findsOneWidget);
  });

  // Ce test garde le MÉCANISME, pas un libellé : il échoue si `tr()` cesse de
  // suivre la langue choisie, ou si une clé manque dans un des catalogues.
  // C'est le filet des lots de traduction qui restent à passer.
  testWidgets('la langue choisie change les libellés', (tester) async {
    await langue.setLocale('en');
    await tester.pumpWidget(monter());
    expect(find.text('Create an account'), findsOneWidget);

    await langue.setLocale('zh');
    await tester.pumpAndSettle();
    expect(find.text('创建账户'), findsOneWidget);
  });
}
