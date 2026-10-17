// LA BANDE « À PARTIR D'ICI, CHIFFRÉ » — juste avant le premier message chiffré.
//
// 🐛 Signalé le 28/09/2026 : sur mobile, elle s'affichait tout en haut du fil,
// au-dessus de messages en clair.

import 'package:alanya/features/chat/frontiere_chiffrement.dart';
import 'package:alanya/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

Message _m(String id, {bool chiffre = false}) => Message(
      id: id,
      convId: 'fil',
      senderId: 'bob',
      content: id,
      type: 'TEXT',
      status: 'SENT',
      replyToId: null,
      media: const [],
      createdAt: DateTime(2026, 9, 28),
      chiffre: chiffre,
    );

void main() {
  test('juste avant le premier message chiffré, pas en tête du fil', () {
    final fil = [_m('clair 1'), _m('clair 2'), _m('chiffré 1', chiffre: true), _m('chiffré 2', chiffre: true)];
    expect(indiceFrontiere(fil), 2);
  });

  test('aucun message chiffré : pas de bande', () {
    expect(indiceFrontiere([_m('a'), _m('b')]), isNull);
    expect(indiceFrontiere(const []), isNull);
  });

  test('un fil chiffré depuis le début : la bande est en tête', () {
    expect(indiceFrontiere([_m('a', chiffre: true)]), 0);
  });

  test('les éléments qui ne sont pas des messages sont ignorés', () {
    expect(indiceFrontiere(['un appel', _m('a'), _m('b', chiffre: true)]), 2);
  });

  test('l’indicateur vient du serveur (`chiffre` dans GET …/messages)', () {
    final m = Message.fromJson({
      'id': 'x',
      'convId': 'fil',
      'senderId': 'bob',
      'content': null,
      'type': 'TEXT',
      'status': 'SENT',
      'createdAt': DateTime(2026, 9, 28).toIso8601String(),
      'chiffre': true,
    });
    expect(m.chiffre, isTrue);
  });
}
