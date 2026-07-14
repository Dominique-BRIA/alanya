import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/features/auth/screens/welcome_screen.dart';

void main() {
  testWidgets("L'écran d'accueil affiche le titre de bienvenue", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));

    expect(find.text("Bienvenue sur Alanya"), findsOneWidget);
    expect(find.text("Créer un compte"), findsOneWidget);
    expect(find.text("J'ai déjà un compte"), findsOneWidget);
  });
}
