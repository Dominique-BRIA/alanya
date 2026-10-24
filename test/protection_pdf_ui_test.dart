import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/features/chat/widgets/infos_protection_pdf.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:alanya/widgets/dialogue_protection_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocaleController langue;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    langue = LocaleController();
  });

  Widget appli(Widget corps) => ChangeNotifierProvider<LocaleController>.value(
    value: langue,
    child: MaterialApp(home: Scaffold(body: corps)),
  );

  group('dialogue de protection à l\'envoi', () {
    late ChoixProtectionPdf? choix;
    late bool ferme;

    Future<void> ouvrir(WidgetTester tester) async {
      ferme = false;
      choix = null;
      await tester.pumpWidget(
        appli(
          Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                choix = await demanderProtectionPdf(c, nombre: 1);
                ferme = true;
              },
              child: const Text('envoyer'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('envoyer'));
      await tester.pumpAndSettle();
    }

    testWidgets('par défaut : aucune protection (comme avant)', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.byKey(const Key('pdfp_valider')));
      await tester.pumpAndSettle();
      expect(ferme, isTrue);
      expect(choix, isNotNull);
      expect(choix!.protection, isNull);
    });

    testWidgets('annuler rend null : rien ne part', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(ferme, isTrue);
      expect(choix, isNull);
    });

    testWidgets('impression interdite sans mot de passe : propriétaire au hasard', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(find.byKey(const Key('pdfp_imprimer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdfp_valider')));
      await tester.pumpAndSettle();
      final p = choix!.protection!;
      expect(p.imprimer, isFalse);
      expect(p.avecMotDePasse, isFalse);
      expect(p.proprietaire.length, 24);
    });

    testWidgets('deux mots de passe : trop courts, identiques, puis valides', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(find.byKey(const Key('pdfp_mot_de_passe')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('pdfp_ouverture')), 'ab');
      await tester.enterText(find.byKey(const Key('pdfp_proprietaire')), 'ab');
      await tester.tap(find.byKey(const Key('pdfp_valider')));
      await tester.pumpAndSettle();
      expect(ferme, isFalse);
      expect(find.text('4 caractères au moins.'), findsNWidgets(2));

      await tester.enterText(find.byKey(const Key('pdfp_ouverture')), 'secret1');
      await tester.enterText(find.byKey(const Key('pdfp_proprietaire')), 'secret1');
      await tester.tap(find.byKey(const Key('pdfp_valider')));
      await tester.pumpAndSettle();
      expect(ferme, isFalse);
      expect(
        find.text('Il doit être différent du mot de passe d\'ouverture.'),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('pdfp_proprietaire')), 'patron22');
      await tester.tap(find.byKey(const Key('pdfp_valider')));
      await tester.pumpAndSettle();
      final p = choix!.protection!;
      expect(p.imprimer, isTrue);
      expect(p.ouverture, 'secret1');
      expect(p.proprietaire, 'patron22');
    });
  });

  group('sous le PDF dans la bulle', () {
    const protection = ProtectionPdf(
      imprimer: false,
      ouverture: 'secret1',
      proprietaire: 'patron22',
    );

    Widget bulle({required bool isMe}) => appli(
      const InfosProtectionPdf(
        protection: protection,
        mediaId: 'media-1',
        isMe: true,
        couleurDiscrete: Colors.grey,
      ).copier(isMe: isMe),
    );

    testWidgets('l\'expéditeur voit les deux mots de passe en clair', (
      tester,
    ) async {
      await tester.pumpWidget(bulle(isMe: true));
      await tester.pumpAndSettle();
      expect(find.textContaining('secret1', findRichText: true), findsOneWidget);
      expect(find.textContaining('patron22', findRichText: true), findsOneWidget);
      expect(find.text('Impression interdite'), findsOneWidget);
      expect(find.byKey(const Key('pdfp_voir')), findsNothing);
    });

    testWidgets('le destinataire le voit UNE fois, jamais le propriétaire', (
      tester,
    ) async {
      await tester.pumpWidget(bulle(isMe: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('secret1', findRichText: true), findsNothing);
      expect(find.textContaining('patron22', findRichText: true), findsNothing);

      await tester.tap(find.byKey(const Key('pdfp_voir')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pdfp_mdp_revele')), findsOneWidget);
      expect(find.textContaining('patron22', findRichText: true), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pdfp_voir')), findsNothing);
      expect(find.text('Mot de passe déjà affiché'), findsOneWidget);

      // Une nouvelle bulle (fil rouvert) se souvient de la vue.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(bulle(isMe: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pdfp_voir')), findsNothing);
      expect(find.text('Mot de passe déjà affiché'), findsOneWidget);
    });
  });
}

extension on InfosProtectionPdf {
  InfosProtectionPdf copier({required bool isMe}) => InfosProtectionPdf(
    protection: protection,
    mediaId: mediaId,
    isMe: isMe,
    couleurDiscrete: couleurDiscrete,
  );
}
