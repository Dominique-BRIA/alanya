// LES MÉDIAS D'UNE CONVERSATION POUR LA GALERIE — en clair ET chiffrés.
//
// 🐛 La galerie écartait les médias chiffrés : toucher l'un d'eux ouvrait une
// page qui ne montrait que lui, et l'on ne pouvait plus glisser d'un média à
// l'autre (user, 03/10/2026).

import 'package:alanya/features/chat/medias_partages.dart';
import 'package:alanya/models/message.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';

Message _msg(String id, MessageMedia media,
        {DescripteurMedia? d, bool vueUnique = false}) =>
    Message(
      id: id,
      convId: 'c',
      senderId: 'a',
      content: null,
      type: 'IMAGE',
      status: 'SENT',
      replyToId: null,
      media: [media],
      createdAt: DateTime(2026, 10, 3),
      mediaChiffre: d,
      vueUnique: vueUnique,
    );

DescripteurMedia _d(String id, String mime) => DescripteurMedia(
    id: id, cle: 'k', empreinte: 'e', taille: 1, mime: mime, nom: '$id.bin');

void main() {
  final clair = _msg('m1',
      MessageMedia(id: 'f1', url: '/api/media/f1', mimeType: 'image/jpeg'));
  final chiffreAvecCle = _msg(
      'm2',
      MessageMedia(
          id: 'f2', url: '/api/media/f2', mimeType: 'application/octet-stream', chiffre: true),
      d: _d('f2', 'video/mp4'));
  final chiffreSansCle = _msg(
      'm3',
      MessageMedia(
          id: 'f3', url: '/api/media/f3', mimeType: 'application/octet-stream', chiffre: true));
  final vueUnique = _msg('m4',
      MessageMedia(id: 'f4', url: '/api/media/f4', mimeType: 'image/jpeg'),
      vueUnique: true);
  final document = _msg(
      'm5',
      MessageMedia(
          id: 'f5', url: '/api/media/f5', mimeType: 'application/octet-stream', chiffre: true),
      d: _d('f5', 'application/pdf'));

  test('clair et chiffré se suivent dans la galerie, le reste en est écarté', () {
    final items = mediasGalerie(
        [clair, chiffreAvecCle, chiffreSansCle, vueUnique, document],
        baseUrl: 'https://x', token: 'j');
    expect(items.map((i) => i.id), ['f1', 'f2']);

    expect(items[0].chiffre, isNull);
    expect(items[0].url, 'https://x/api/media/f1?token=j');

    expect(items[1].chiffre?.id, 'f2');
    expect(items[1].isVideo, isTrue);
    expect(items[1].url, isEmpty, reason: 'le fichier du serveur est illisible');
  });

  test('la clé peut venir du cache local plutôt que du message', () {
    final items = mediasGalerie([chiffreSansCle],
        baseUrl: 'https://x',
        token: 'j',
        chiffreDe: (m) => m.id == 'm3' ? _d('f3', 'image/png') : null);
    expect(items.single.chiffre?.id, 'f3');
    expect(items.single.isVideo, isFalse);
  });
}
