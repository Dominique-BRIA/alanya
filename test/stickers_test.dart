import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alanya/core/api_client.dart';
import 'package:alanya/core/authed_api.dart';
import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/features/stickers/bulle_sticker.dart';
import 'package:alanya/features/stickers/creer_sticker_screen.dart';
import 'package:alanya/features/stickers/image_sticker.dart';
import 'package:alanya/features/stickers/stickers_service.dart';
import 'package:alanya/models/message_payload.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:alanya/widgets/selecteur_emojis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un faux serveur : il note les appels et rend le catalogue du banc.
class _FauxApi implements AuthedApi {
  final appels = <String>[];
  bool ouverts = true;
  bool refuser = false;

  static Map<String, dynamic> _sticker(int id, int asset, String emoji, String nom) => {
    'id': id,
    'assetId': asset,
    'emoji': emoji,
    'nom': {'fr': nom},
    'url': 'https://exemple.test/api/stickers/fichier/$asset',
    'anime': false,
  };

  @override
  Future<Map<String, dynamic>> get(String path) async {
    appels.add('GET $path');
    if (path == '/api/stickers') {
      return {
        'enabled': ouverts,
        'packs': ouverts
            ? [
                {
                  'id': 1,
                  'code': 'salutations',
                  'nom': {'fr': 'Salutations', 'en': 'Greetings'},
                  'stickers': [_sticker(11, 101, '👋', 'coucou'), _sticker(12, 102, '🙏', 'merci')],
                },
                {
                  'id': 2,
                  'code': 'fete',
                  'nom': {'fr': 'Fête'},
                  'stickers': [_sticker(21, 201, '🎉', 'bravo')],
                },
              ]
            : [],
      };
    }
    if (path == '/api/stickers/me') {
      return {
        'packs': [
          {'id': 2, 'code': 'fete', 'position': 0},
          {'id': 1, 'code': 'salutations', 'position': 1},
        ],
        'favorites': [12],
        'features': {'creation': creation},
        'created': creation && creees.isNotEmpty
            ? {
                'id': 9,
                'code': 'perso-moi',
                'nom': {'fr': 'Mes créations'},
                'stickers': [for (final id in creees) _sticker(id, id + 1000, '', 'à moi')],
              }
            : null,
      };
    }
    throw ApiException(404, 'Introuvable');
  }

  bool creation = true;
  final creees = <int>[91];
  Uint8List? dernierEnvoi;

  @override
  Future<Map<String, dynamic>> uploadBytes(
    String path,
    Uint8List bytes,
    String filename,
    String mimeType, {
    Map<String, String>? fields,
    void Function(int envoyes, int total)? onProgress,
  }) async {
    appels.add('UPLOAD $path $mimeType');
    dernierEnvoi = bytes;
    creees.insert(0, 92);
    return {'stickerId': 92, 'assetId': 1092, 'packId': 9};
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    appels.add('POST $path');
    if (path.endsWith('/copy')) creees.insert(0, 93);
    return {};
  }

  @override
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    appels.add('PUT $path ${jsonEncode(body)}');
    if (refuser) throw ApiException(409, 'Limite');
    return {};
  }

  @override
  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? body}) async {
    appels.add('DELETE $path');
    if (refuser) throw ApiException(500, 'Panne');
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('format', () {
    test('la charge : mêmes clés, même ordre que le serveur', () {
      const s = Sticker(id: 12, assetId: 40, packCode: 'salutations', emoji: '👋', url: 'u');
      expect(
        s.charge(),
        '{"v":1,"pack":"salutations","sid":12,"asset":40,"emoji":"👋","w":512,"h":512,"a":0}',
      );
      final lu = ChargeSticker.lire(s.charge())!;
      expect(lu.sid, 12);
      expect(lu.assetId, 40);
      expect(lu.url, endsWith('/api/stickers/fichier/40'));
    });

    test('une charge illisible ou d\'une autre version → null', () {
      expect(ChargeSticker.lire(null), isNull);
      expect(ChargeSticker.lire('salut'), isNull);
      expect(ChargeSticker.lire('{"v":2,"pack":"p","sid":1,"asset":2}'), isNull);
      expect(ChargeSticker.lire('{"v":1,"pack":"p","sid":"1","asset":2}'), isNull);
    });

    test('l\'aperçu dit « Sticker », comme le serveur', () {
      expect(apercuMessage('STICKER', '{"v":1,"pack":"p","sid":1,"asset":2,"emoji":"👋"}'), '👋 Sticker');
      expect(apercuMessage('STICKER', '{"v":1,"pack":"p","sid":1,"asset":2}'), 'Sticker');
      expect(apercuMessage('STICKER', 'illisible'), 'Sticker');
    });

    test('dans un fil chiffré, le genre STICKER survit à la charge', () {
      const s = Sticker(id: 1, assetId: 2, packCode: 'p', emoji: '', url: 'u');
      final clair = ecrireCharge('msg-1', s.charge(), null, null, 'STICKER');
      final c = lireCharge(clair, 'msg-1');
      expect(c.genre, 'STICKER');
      expect(ChargeSticker.lire(c.texte)?.sid, 1);
    });
  });

  group('StickersService', () {
    test('charge le catalogue et MON panneau, dans mon ordre', () async {
      final api = _FauxApi();
      final s = StickersService(api)..suivreCompte('moi');
      await s.assurer();
      expect(s.ouverts, isTrue);
      expect(s.packsInstalles.map((p) => p.code), ['fete', 'salutations']);
      expect(s.stickersFavoris.map((x) => x.id), [12]);
      expect(s.chercher('merci').map((x) => x.id), [12]);
      expect(s.chercher('🎉').map((x) => x.id), [21]);
    });

    test('fermés : pas de panneau, /me n\'est pas demandé', () async {
      final api = _FauxApi()..ouverts = false;
      final s = StickersService(api)..suivreCompte('moi');
      await s.assurer();
      expect(s.ouverts, isFalse);
      expect(api.appels, ['GET /api/stickers']);
    });

    test('retirer, puis un refus du serveur remet l\'état d\'avant', () async {
      final api = _FauxApi();
      final s = StickersService(api)..suivreCompte('moi');
      await s.assurer();
      await s.retirer(1);
      expect(s.mesPacks, [2]);
      expect(api.appels.last, 'DELETE /api/stickers/me/packs/1');
      api.refuser = true;
      await expectLater(s.installer(1), throwsA(isA<ApiException>()));
      expect(s.mesPacks, [2]);
    });

    test('favori : ajouté en tête, retiré ; récents limités à cet appareil', () async {
      final api = _FauxApi();
      final s = StickersService(api)..suivreCompte('moi');
      await s.assurer();
      await s.basculerFavori(11);
      expect(s.favoris, [11, 12]);
      expect(api.appels.last, startsWith('PUT /api/stickers/me/favorites/11'));
      await s.basculerFavori(12);
      expect(s.favoris, [11]);
      await s.noterRecent(21);
      await s.noterRecent(11);
      await s.noterRecent(21);
      expect(s.recents, [21, 11]);
    });

    test('un autre compte sur le même téléphone ne voit rien du premier', () async {
      final api = _FauxApi();
      final s = StickersService(api)..suivreCompte('dbria');
      await s.assurer();
      await s.noterRecent(21);
      s.suivreCompte('doms');
      expect(s.mesPacks, isEmpty);
      expect(s.favoris, isEmpty);
      expect(s.recents, isEmpty);
    });
  });

  group('écrans', () {
    late _FauxApi api;
    late StickersService service;

    Widget appli(Widget corps) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>(create: (_) => LocaleController()),
        ChangeNotifierProvider<StickersService>.value(value: service),
      ],
      child: MaterialApp(home: Scaffold(body: corps)),
    );

    setUp(() async {
      api = _FauxApi();
      service = StickersService(api)..suivreCompte('moi');
      await service.assurer();
    });

    testWidgets('l\'onglet Stickers : un toucher envoie le sticker', (tester) async {
      Sticker? envoye;
      await tester.pumpWidget(appli(SizedBox(
        height: 320,
        child: SelecteurEmojis(onChoisir: (_) {}, onSticker: (s) => envoye = s),
      )));
      await tester.pump();
      expect(find.byKey(const Key('onglet_stickers')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onglet_stickers')));
      await tester.pump();
      // Sans récents, le panneau s'ouvre sur MON premier pack : « Fête ».
      await tester.tap(find.byKey(const ValueKey('sticker-21')));
      expect(envoye?.id, 21);
    });

    testWidgets('sans onSticker (statuts), pas d\'onglet Stickers', (tester) async {
      await tester.pumpWidget(appli(SizedBox(height: 320, child: SelecteurEmojis(onChoisir: (_) {}))));
      await tester.pump();
      expect(find.byKey(const Key('onglet_stickers')), findsNothing);
    });

    testWidgets('fermés par la console : pas d\'onglet Stickers', (tester) async {
      api.ouverts = false;
      await service.rafraichir();
      await tester.pumpWidget(appli(SizedBox(
        height: 320,
        child: SelecteurEmojis(onChoisir: (_) {}, onSticker: (_) {}),
      )));
      await tester.pump();
      expect(find.byKey(const Key('onglet_stickers')), findsNothing);
    });

    testWidgets('un sticker reçu : favori, et « Voir le pack »', (tester) async {
      await tester.pumpWidget(appli(BulleSticker(
        charge: ChargeSticker.lire(
          '{"v":1,"pack":"salutations","sid":11,"asset":101,"emoji":"👋"}',
        )!,
        timestamp: '12:00',
      )));
      await tester.tap(find.byType(ImageSticker));
      await tester.pumpAndSettle();
      // Le nom du pack dans la langue de l'appareil de test (fr ou en).
      expect(find.text('Salutations').evaluate().length + find.text('Greetings').evaluate().length, 1);
      expect(find.byKey(const Key('sticker_voir_pack')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sticker_favori')));
      await tester.pumpAndSettle();
      expect(service.estFavori(11), isTrue);
    });
  });

  group('créer ses stickers', () {
    test('/me : création ouverte, « Mes créations » se lit et se trouve', () async {
      final api = _FauxApi();
      final s = StickersService(api)..suivreCompte('moi');
      await s.assurer();
      expect(s.creation, isTrue);
      expect(s.creations?.stickers.map((x) => x.id), [91]);
      expect(s.estMaCreation(91), isTrue);
      expect(s.sticker(91)?.packCode, 'perso-moi');
      expect(s.chercher('à moi').map((x) => x.id), [91]);
    });

    test('supprimer une création, copier un sticker reçu', () async {
      final api = _FauxApi();
      final s = StickersService(api)..suivreCompte('moi');
      await s.assurer();
      await s.supprimerCreation(91);
      expect(s.creations?.stickers, isEmpty);
      expect(api.appels.last, 'DELETE /api/stickers/stickers/91');
      api.creees.clear();
      await s.copier(55);
      expect(api.appels, contains('POST /api/stickers/stickers/55/copy'));
      expect(s.estMaCreation(93), isTrue);
    });

    test('création fermée : pas de « Mes créations »', () async {
      final api = _FauxApi()..creation = false;
      final s = StickersService(api)..suivreCompte('moi');
      await s.assurer();
      expect(s.creation, isFalse);
      expect(s.creations, isNull);
    });

    testWidgets('l\'écran capture le cadre en PNG de 512 px, et rend le sticker', (tester) async {
      final api = _FauxApi();
      final service = StickersService(api)..suivreCompte('moi');
      await tester.runAsync(service.assurer);
      // Une vraie photo : 8 × 8 pixels rouges.
      final photo = await tester.runAsync(() async {
        final r = ui.PictureRecorder();
        ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.red);
        final img = await r.endRecording().toImage(8, 8);
        return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      });
      Sticker? rendu;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>(create: (_) => LocaleController()),
          ChangeNotifierProvider<StickersService>.value(value: service),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async => rendu = await Navigator.of(c).push<Sticker>(
                MaterialPageRoute(builder: (_) => CreerStickerScreen(photo: photo)),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('creer_texte')), 'Salut');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('creer_envoyer')),
        200,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('creer_envoyer')));
        for (var i = 0; i < 50 && rendu == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(api.appels, contains('UPLOAD /api/stickers/assets image/png'));
      final octets = api.dernierEnvoi!;
      // La signature PNG, et 512 × 512 dans l'en-tête IHDR.
      expect(octets.sublist(1, 4), 'PNG'.codeUnits);
      final entete = ByteData.sublistView(octets, 16, 24);
      expect(entete.getUint32(0), 512);
      expect(entete.getUint32(4), 512);
      expect(rendu?.id, 92);
    });
  });
}
