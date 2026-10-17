// QUI TRANSFÈRE : LE SERVEUR, OU L'APPAREIL ? (07/10/2026, cours ch. 29)
//
// Le serveur recopie une ligne ; il ne peut le faire ni depuis un fil chiffré
// (il n'a pas le contenu), ni vers un fil chiffré (il y écrirait du clair).

import 'package:alanya/features/chat/transfert_appareil.dart';
import 'package:alanya/models/conversation.dart';
import 'package:alanya/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

Message _m({bool chiffre = false}) => Message(
      id: 'm',
      chiffre: chiffre,
      convId: 'source',
      senderId: 'moi',
      content: 'Bonjour',
      type: 'TEXT',
      status: 'SENT',
      replyToId: null,
      media: const [],
      createdAt: DateTime(2026, 10, 7),
    );

void main() {
  test('fil ordinaire vers fil ordinaire : le serveur', () {
    expect(transfertParLAppareil(_m(), sourceChiffree: false, cibleChiffree: false), isFalse);
  });

  test('LE DÉFAUT : depuis ou vers un fil chiffré, l’appareil', () {
    expect(transfertParLAppareil(_m(chiffre: true), sourceChiffree: true, cibleChiffree: false), isTrue);
    expect(transfertParLAppareil(_m(), sourceChiffree: false, cibleChiffree: true), isTrue);
  });

  test('le correspondant d’un tête-à-tête, pas d’un groupe', () {
    Conversation conv(bool groupe) => Conversation.fromJson({
          'id': 'c',
          'isGroup': groupe,
          'title': 'Bob',
          'members': [
            {'id': 'moi', 'publicNumber': '1', 'isOnline': 0},
            {'id': 'bob', 'publicNumber': '2', 'isOnline': 0},
          ],
          'unread': 0,
          'updatedAt': DateTime(2026, 10, 7).toIso8601String(),
          'e2eeActif': true,
        });
    expect(correspondantDe(conv(false), 'moi'), 'bob');
    expect(correspondantDe(conv(true), 'moi'), isNull);
  });

  test('le type de message suit le vrai type du fichier', () {
    expect(typePourMime('image/jpeg'), 'IMAGE');
    expect(typePourMime('video/mp4'), 'VIDEO');
    expect(typePourMime('audio/mp4'), 'AUDIO');
    expect(typePourMime('application/pdf'), 'FILE');
  });
}
