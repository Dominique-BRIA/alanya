// LA LIGNE « 4,2 Mo → 320 Ko · Meilleure qualité » DE L'ÉCRAN D'ENVOI.
//
// 🐛 ELLE NE S'AFFICHAIT PAS SUR LE MOBILE (signalé par le user le 13/10/2026 :
// « même quand ça doit compresser, ça n'affiche pas ça sur le mobile »). Elle
// ne devait manquer que dans un seul cas : quand rien n'a été compressé.
//
// ⚠️ ON MONTE L'ÉCRAN ENTIER, et non la seule fonction : le défaut peut être
// dans la condition comme dans ce qui l'alimente. Un test de la condition seule
// aurait été vert pendant que l'écran restait muet.

import 'dart:convert';
import 'dart:typed_data';

import 'package:alanya/core/compression_image.dart';
import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/features/chat/screens/media_caption_screen.dart';
import 'package:alanya/widgets/media/media_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un VRAI PNG de 1 × 1 : l'écran monte un aperçu, et des octets quelconques
/// feraient échouer le décodeur avant même d'arriver à la ligne qu'on teste.
final Uint8List _pngReel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

MediaPickResult _photo({
  required bool compresse,
  int? tailleOriginale,
  String? path = '/tmp/photo.jpg',
  bool niveauSuperieurPossible = true,
  NiveauQualite niveau = NiveauQualite.normal,
}) =>
    MediaPickResult(
      bytes: _pngReel,
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      path: path,
      compresse: compresse,
      tailleOriginale: tailleOriginale,
      niveauSuperieurPossible: niveauSuperieurPossible,
      niveau: niveau,
    );

Future<void> _monter(WidgetTester tester, MediaPickResult m) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => LocaleController(),
      child: MaterialApp(
        home: MediaCaptionScreen(files: [m], membres: const {}, monId: "moi"),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('une photo compressée annonce son gain et propose mieux',
      (tester) async {
    await _monter(
      tester,
      _photo(compresse: true, tailleOriginale: 4 * 1024 * 1024),
    );
    expect(find.textContaining('→'), findsOneWidget,
        reason: 'la flèche « avant → après » doit paraître');
    expect(find.byIcon(Icons.compress), findsOneWidget);
  });

  testWidgets('rien de compressé : aucune ligne, et c\'est voulu',
      (tester) async {
    await _monter(tester, _photo(compresse: false));
    expect(find.byIcon(Icons.compress), findsNothing);
  });

  testWidgets('compressée mais sans taille d\'origine : la ligne paraît quand même',
      (tester) async {
    // 🐛 LA CAUSE DU DÉFAUT. Un sélecteur qui remplit `compresse` sans
    // `tailleOriginale` faisait disparaître toute la ligne, bouton compris —
    // alors qu'il y avait bien eu compression, et donc quelque chose à dire.
    await _monter(tester, _photo(compresse: true, tailleOriginale: null));
    expect(find.byIcon(Icons.compress), findsOneWidget,
        reason: 'la ligne doit paraître dès qu\'une compression a eu lieu');
  });

  testWidgets('sans chemin de fichier, pas de bouton — on ne promet pas ce '
      'qu\'on ne peut pas tenir', (tester) async {
    await _monter(
      tester,
      _photo(compresse: true, tailleOriginale: 4 * 1024 * 1024, path: null),
    );
    expect(find.byIcon(Icons.compress), findsOneWidget,
        reason: 'le gain se dit quand même');
  });
}
