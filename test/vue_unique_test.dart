// MESSAGES À VUE UNIQUE — modèle, cache local, bulle.
//
// Demandé le 02/10/2026 (« comme dans WhatsApp »). Le serveur garantit
// l'unicité de la vue et l'effacement ; ici on prouve que l'application ne
// PERD pas le drapeau en route — un message relu du cache ou recopié qui
// redeviendrait une photo ordinaire tenterait d'afficher sa vignette.

import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/core/message_cache.dart';
import 'package:alanya/features/chat/widgets/bulle_vue_unique.dart';
import 'package:alanya/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Message _photo({
  String senderId = 'alice',
  bool ouverte = false,
  bool effacee = false,
}) =>
    Message.fromJson({
      'id': 'm1',
      'convId': 'c1',
      'senderId': senderId,
      'content': null,
      'type': 'IMAGE',
      'status': 'DELIVERED',
      'replyToId': null,
      'media': [
        {
          'id': 'f1',
          'url': '/api/media/f1',
          'filename': 'secret.jpg',
          'mimeType': 'image/jpeg',
          'sizeBytes': 10,
        }
      ],
      'createdAt': '2026-10-02T10:00:00.000Z',
      'vueUnique': true,
      'vueUniqueOuverte': ouverte,
      'vueUniqueEffacee': effacee,
    });

void main() {
  group('modèle', () {
    test('le serveur annonce la vue unique et son état', () {
      final m = _photo(ouverte: true);
      expect(m.vueUnique, isTrue);
      expect(m.vueUniqueOuverte, isTrue);
      expect(m.vueUniqueEffacee, isFalse);
    });

    test('un message ordinaire n’est pas à vue unique', () {
      final m = Message.fromJson({
        'id': 'm2',
        'convId': 'c1',
        'senderId': 'a',
        'content': 'salut',
        'type': 'TEXT',
        'replyToId': null,
        'createdAt': '2026-10-02T10:00:00.000Z',
      });
      expect(m.vueUnique, isFalse);
    });

    test('changer le statut GARDE la vue unique (sinon la vignette réapparaît)', () {
      final m = _photo().avecStatut('READ');
      expect(m.status, 'READ');
      expect(m.vueUnique, isTrue);
    });

    test('avecVueUnique ne touche qu’à l’état demandé', () {
      final m = _photo().avecVueUnique(ouverte: true);
      expect(m.vueUniqueOuverte, isTrue);
      expect(m.vueUniqueEffacee, isFalse);
      expect(m.media.single.id, 'f1');
      expect(m.avecVueUnique(effacee: true).vueUniqueOuverte, isTrue);
    });
  });

  group('cache local (v7)', () {
    test('les trois états tiennent dans un entier', () {
      expect(MessageCache.bitsVueUnique(_photo()), 1);
      expect(MessageCache.bitsVueUnique(_photo(ouverte: true)), 3);
      expect(MessageCache.bitsVueUnique(_photo(ouverte: true, effacee: true)), 7);
      final ordinaire = Message.fromJson({
        'id': 'm2',
        'convId': 'c1',
        'senderId': 'a',
        'content': 'x',
        'type': 'TEXT',
        'replyToId': null,
        'createdAt': '2026-10-02T10:00:00.000Z',
      });
      expect(MessageCache.bitsVueUnique(ordinaire), 0);
    });
  });

  group('ouvrable', () {
    test('seul le DESTINATAIRE, avant d’avoir ouvert, peut ouvrir', () {
      expect(BulleVueUnique.ouvrable(_photo(), isMe: false), isTrue);
      expect(BulleVueUnique.ouvrable(_photo(), isMe: true), isFalse,
          reason: 'l’expéditeur ne rouvre pas son envoi');
      expect(BulleVueUnique.ouvrable(_photo(ouverte: true), isMe: false), isFalse);
      expect(BulleVueUnique.ouvrable(_photo(effacee: true), isMe: false), isFalse);
    });
  });

  group('bulle', () {
    late LocaleController langue;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      langue = LocaleController();
    });

    Future<void> afficher(WidgetTester tester, Message m,
        {required bool isMe, VoidCallback? onOuvrir}) {
      return tester.pumpWidget(ChangeNotifierProvider<LocaleController>.value(
        value: langue,
        child: MaterialApp(
          home: Scaffold(
            body: BulleVueUnique(
              message: m,
              isMe: isMe,
              couleurAccent: Colors.orange,
              couleurDiscrete: Colors.grey,
              timestamp: '10:00',
              onOuvrir: onOuvrir,
            ),
          ),
        ),
      ));
    }

    testWidgets('destinataire : « Appuyez pour ouvrir », et l’appui ouvre',
        (tester) async {
      var ouvertures = 0;
      await afficher(tester, _photo(), isMe: false, onOuvrir: () => ouvertures++);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Appuyez pour ouvrir'), findsOneWidget);
      expect(find.byType(Image), findsNothing, reason: 'aucune vignette, jamais');
      await tester.tap(find.byType(BulleVueUnique));
      expect(ouvertures, 1);
    });

    testWidgets('expéditeur : « Envoyée » puis « Ouverte »', (tester) async {
      await afficher(tester, _photo(), isMe: true);
      expect(find.text('Envoyée'), findsOneWidget);
      await afficher(tester, _photo(ouverte: true), isMe: true);
      expect(find.text('Ouverte'), findsOneWidget);
    });
  });
}
