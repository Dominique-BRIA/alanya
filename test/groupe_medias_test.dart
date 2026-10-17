// LA LÉGENDE D'UN LOT DE MÉDIAS — affichée sous la grille, comme sur le web.

import 'package:alanya/features/chat/groupe_medias.dart';
import 'package:alanya/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

Message _photo(String id, {String legende = ''}) => Message(
  id: id,
  convId: 'c',
  senderId: 'moi',
  content: legende,
  type: 'IMAGE',
  status: 'SENT',
  replyToId: null,
  media: const [],
  createdAt: DateTime(2026, 10, 3),
);

void main() {
  test('un lot sans légende n\'en affiche aucune', () {
    expect(GroupeMedias([_photo('a'), _photo('b')]).legende, isNull);
  });

  test('la légende d\'un lot, où qu\'elle soit dans le lot', () {
    expect(
      GroupeMedias([_photo('a'), _photo('b', legende: ' Top '), _photo('c')])
          .legende,
      'Top',
    );
  });
}
