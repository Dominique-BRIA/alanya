import 'dart:io';

import 'package:alanya/features/calls/effets_video.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les effets de visage en appel vidéo (18/10/2026) : le côté Dart.
///
/// Le dessin lui-même est natif (`EffetsVisage.kt`) et ne se teste qu'au
/// téléphone ; ici on vérifie ce qui peut casser sans bruit : un libellé
/// oublié, un choix qui survit à la fin de l'appel, un refus mal remonté.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('alanya/effets_video');
  final appels = <MethodCall>[];

  setUp(() {
    appels.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (appel) async {
      appels.add(appel);
      return appel.method == 'appliquer';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  test("chaque effet a son libellé", () {
    final catalogue = File("lib/l10n/app_localizations.dart").readAsStringSync();
    for (final e in EffetsVideo.effets) {
      expect(catalogue.contains("'fx_$e':"), isTrue, reason: "fx_$e manque");
    }
    expect(EffetsVideo.effets.first, 'aucun');
  });

  test("sans piste caméra, rien n'est demandé au natif", () async {
    expect(await EffetsVideo.appliquer(null, 'barbe'), isFalse);
    expect(appels, isEmpty);
    expect(EffetsVideo.actuel.value, 'aucun');
  });

  test("l'effet choisi est retenu, puis effacé à la fin de l'appel", () async {
    expect(await EffetsVideo.appliquer('piste-1', 'lunettes'), isTrue);
    expect(appels.single.arguments, {'trackId': 'piste-1', 'effet': 'lunettes'});
    expect(EffetsVideo.actuel.value, 'lunettes');

    await EffetsVideo.retirer();
    expect(EffetsVideo.actuel.value, 'aucun');
    expect(appels.last.method, 'retirer');
  });

  test("le diagnostic dit pourquoi l'effet ne se voit pas", () {
    Map<String, dynamic> e(Map<String, dynamic> m) =>
        {'effet': 'barbe', 'images': 40, 'visages': 0, ...m};
    expect(EffetsVideo.diagnostic(null), isNull);
    expect(EffetsVideo.diagnostic({'effet': 'aucun'}), isNull);
    expect(EffetsVideo.diagnostic(e({'visages': 12})), isNull);
    expect(EffetsVideo.diagnostic(e({'detecteur': 'UnsatisfiedLinkError'})),
        'fx_diag_detecteur');
    expect(EffetsVideo.diagnostic(e({'images': 0})), 'fx_diag_images');
    expect(EffetsVideo.diagnostic(e({'erreur': 'IllegalStateException'})),
        'fx_diag_erreur');
    expect(EffetsVideo.diagnostic(e({})), 'fx_diag_visage');
    final catalogue = File("lib/l10n/app_localizations.dart").readAsStringSync();
    for (final k in ['fx_diag_detecteur', 'fx_diag_images', 'fx_diag_erreur', 'fx_diag_visage']) {
      expect(catalogue.contains("'$k':"), isTrue, reason: "$k manque");
    }
  });

  test("un refus du natif ne change pas l'effet affiché", () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (_) async => false);
    expect(await EffetsVideo.appliquer('piste-1', 'barbe'), isFalse);
    expect(EffetsVideo.actuel.value, 'aucun');
  });
}
