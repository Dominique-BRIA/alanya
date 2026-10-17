// LE DERNIER MESSAGE D'UN FIL CHIFFRÉ DANS LA LISTE — `appliquerDerniersTextes`.
//
// Demande du user, 28/09/2026 : le serveur n'a pas le texte d'un fil chiffré
// (il rend `lastMessage: null`) ; la liste doit montrer celui que l'appareil a
// déchiffré et rangé dans son cache.

import 'package:alanya/features/home/dernier_message_local.dart';
import 'package:alanya/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

LastMessage _dernier(String texte, int minute, {String type = 'TEXT'}) => LastMessage(
      id: 'm$minute',
      content: texte,
      type: type,
      senderId: 'bob',
      createdAt: DateTime(2026, 9, 28, 10, minute),
    );

Conversation _conv(String id, {required bool chiffre, LastMessage? dernier}) =>
    Conversation.fromJson({
      'id': id,
      'isGroup': false,
      'title': 'Bob',
      'members': const [],
      'lastMessage': dernier == null
          ? null
          : {
              'id': dernier.id,
              'content': dernier.content,
              'type': dernier.type,
              'senderId': dernier.senderId,
              'createdAt': dernier.createdAt.toIso8601String(),
            },
      'unread': 2,
      'updatedAt': DateTime(2026, 9, 28).toIso8601String(),
      'e2eeActif': chiffre,
    });

void main() {
  test('fil chiffré sans aperçu serveur : le texte local s’affiche', () {
    final r = appliquerDerniersTextes(
      [_conv('a', chiffre: true)],
      {'a': _dernier('rendez-vous à 14 h', 5)},
    );
    expect(r.single.lastMessage?.content, 'rendez-vous à 14 h');
    expect(r.single.unread, 2, reason: 'le compteur vient du serveur, intact');
  });

  test('un média plus récent, connu du serveur, reste le dernier message', () {
    final r = appliquerDerniersTextes(
      [_conv('a', chiffre: true, dernier: _dernier('📷 Photo', 9, type: 'IMAGE'))],
      {'a': _dernier('ancien texte', 5)},
    );
    expect(r.single.lastMessage?.content, '📷 Photo');
  });

  test('un texte local plus récent que l’aperçu serveur gagne', () {
    final r = appliquerDerniersTextes(
      [_conv('a', chiffre: true, dernier: _dernier('📷 Photo', 5, type: 'IMAGE'))],
      {'a': _dernier('et ça ?', 9)},
    );
    expect(r.single.lastMessage?.content, 'et ça ?');
  });

  test('un fil ORDINAIRE garde l’aperçu du serveur', () {
    final r = appliquerDerniersTextes(
      [_conv('a', chiffre: false, dernier: _dernier('serveur', 1))],
      {'a': _dernier('local', 9)},
    );
    expect(r.single.lastMessage?.content, 'serveur');
  });

  test('rien en local : la conversation est rendue telle quelle', () {
    final c = _conv('a', chiffre: true);
    expect(identical(appliquerDerniersTextes([c], {}).single, c), isTrue);
  });
}
