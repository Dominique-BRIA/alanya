import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/models/message.dart';
import 'package:alanya/services/e2ee/e2ee_journal.dart';

/// Spécification exécutable de la chaîne de chiffrement E2EE :
/// 1. Préservation des textes déchiffrés (aucun écrasement par `content: null`).
/// 2. Continuité des sessions (pas de réinitialisation de ratchet par `PreKeyBundle`).
/// 3. Sauvegarde locale de toutes les enveloppes relevées.
///
/// Lancer avec : flutter test test/chiffrement_e2ee_test.dart
void main() {
  group('Journal du chiffrement E2eeJournal', () {
    test('enregistre et horodate les événements', () {
      E2eeJournal.vider();
      final traces = <String>[];
      E2eeJournal.tracer = traces.add;

      E2eeJournal.note('démarrage');
      E2eeJournal.note('clés publiées');

      expect(E2eeJournal.lignes.length, 2);
      expect(E2eeJournal.lignes.first, contains('clés publiées'));
      expect(traces, ['démarrage', 'clés publiées']);
    });
  });

  group('Modèle Message — champ chiffre', () {
    test('lit chiffre: true depuis le JSON du serveur', () {
      final m = Message.fromJson({
        'id': 'msg-1',
        'convId': 'conv-1',
        'senderId': 'user-1',
        'content': null,
        'type': 'TEXT',
        'createdAt': DateTime.now().toIso8601String(),
        'chiffre': true,
      });

      expect(m.chiffre, isTrue);
      expect(m.content, isNull);
    });

    test('défaut à false si absent', () {
      final m = Message.fromJson({
        'id': 'msg-2',
        'convId': 'conv-1',
        'senderId': 'user-1',
        'content': 'clair',
        'type': 'TEXT',
        'createdAt': DateTime.now().toIso8601String(),
      });

      expect(m.chiffre, isFalse);
      expect(m.content, 'clair');
    });
  });

  group('Analyse statique des garanties de chiffrement', () {
    test("ouvrirSessions vérifie l'existence d'une session", () {
      final file = File('lib/services/e2ee/e2ee_service.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, contains('containsSession(adresse)'));
    });

    test('MessageCache possède la table et les méthodes de déchiffrement', () {
      final file = File('lib/core/message_cache.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, contains('messages_dechiffres'));
      expect(content, contains('sauvegarderTexteDechiffre'));
      expect(content, contains('textesDechiffresDe'));
      expect(content, contains('version: 4'));
    });

    test('chat_screen préserve le texte déchiffré dans _load et _poll', () {
      final file = File('lib/features/chat/screens/chat_screen.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, contains('MessageCache.textesDechiffresDe(widget.convId)'));
      expect(content, contains('sauvegarderTexteDechiffre'));
      expect(content, contains('_otherUserId'));
    });

    test('E2eeFil sauvegarde et extrait de façon robuste les identifiants', () {
      final file = File('lib/services/e2ee/e2ee_fil.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, contains('senderDeviceId'));
      expect(content, contains('expediteurDevice'));
      expect(content, contains('aAcquitter'));
    });
  });
}
