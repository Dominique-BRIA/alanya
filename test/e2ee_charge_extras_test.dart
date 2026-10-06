// LA RÉPONSE ET LE CONTACT DANS UN FIL CHIFFRÉ (06/10/2026).
//
// 🐛 « Le reply sur un message de toute forme ne marche pas », et un contact
// ne partait pas dans un fil chiffré. La charge v2 porte désormais `reponseA`
// (le message cité) et `genre` (CONTACT, LOCATION). Jumeau du banc web
// `STAGE-WEB/scripts/e2ee-charge-reponse-genre.mjs`.

import 'package:alanya/features/chat/fusion_releve.dart';
import 'package:alanya/features/home/dernier_message_local.dart';
import 'package:alanya/models/conversation.dart';
import 'package:alanya/models/message.dart';
import 'package:alanya/services/e2ee/e2ee_fil.dart' show MessageClair;
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '11111111-2222-4333-8444-555555555555';
const _cite = '99999999-8888-4777-8666-555555555555';
const _fiche = '{"v":1,"contacts":[{"name":"Jean","phones":["82312187"]}]}';

/// La charge que le WEB produit pour un contact en réponse — copiée de la
/// sortie ⑤ du banc web. Le téléphone doit la lire, et écrire la même.
const _chargeDuWeb = '\u0000A2{"v":2,"id":"11111111-2222-4333-8444-555555555555",'
    r'"texte":"{\"v\":1,\"contacts\":[{\"name\":\"Jean\",\"phones\":[\"82312187\"]}]}",'
    '"reponseA":"99999999-8888-4777-8666-555555555555","genre":"CONTACT"}';

void main() {
  group('la charge', () {
    test('sans extras : la charge d’avant, octet pour octet', () {
      expect(ecrireCharge(_id, 'Salut'), '\u0000A2{"v":2,"id":"$_id","texte":"Salut"}');
    });

    test('parité : le téléphone écrit EXACTEMENT ce que le web écrit', () {
      expect(ecrireCharge(_id, _fiche, null, _cite, 'CONTACT'), _chargeDuWeb);
    });

    test('parité : le téléphone lit la charge du web', () {
      final c = lireCharge(_chargeDuWeb, _id);
      expect(c.texte, _fiche);
      expect(c.reponseA, _cite);
      expect(c.genre, 'CONTACT');
    });

    test('un genre inconnu et une citation vide sont ignorés', () {
      final c = lireCharge(
          '\u0000A2{"v":2,"id":"$_id","texte":"x","genre":"SONDAGE","reponseA":""}', _id);
      expect(c.genre, isNull);
      expect(c.reponseA, isNull);
    });

    test('rattachée à un autre message : toujours refusée', () {
      expect(() => lireCharge(ecrireCharge(_id, 'x', null, _cite), _cite),
          throwsA(isA<ChargeInvalide>()));
    });
  });

  group('la relève', () {
    MessageClair releve({String? reponseA, String? genre, String texte = 'Oui'}) => (
          id: 'neuf',
          convId: 'fil',
          expediteurId: 'bob',
          texte: texte,
          quand: DateTime(2026, 10, 6, 10).millisecondsSinceEpoch,
          media: null,
          reponseA: reponseA,
          genre: genre,
        );

    test('LE DÉFAUT : une réponse relevée garde sa citation', () {
      final r = fusionnerReleve(const [], [releve(reponseA: _cite)], 'fil');
      expect(r.ajoutes.single.replyToId, _cite);
    });

    test('un contact relevé est un CONTACT, pas un texte JSON', () {
      final r = fusionnerReleve(const [], [releve(genre: 'CONTACT', texte: _fiche)], 'fil');
      expect(r.ajoutes.single.type, 'CONTACT');
      expect(r.ajoutes.single.content, _fiche);
    });

    test('une bulle vide déjà là reçoit sa citation', () {
      final vide = Message(
        id: 'neuf',
        chiffre: true,
        convId: 'fil',
        senderId: 'bob',
        content: null,
        type: 'TEXT',
        status: 'DELIVERED',
        replyToId: null,
        media: const [],
        createdAt: DateTime(2026, 10, 6, 10),
      );
      final r = fusionnerReleve([vide], [releve(reponseA: _cite)], 'fil');
      expect(r.liste.single.replyToId, _cite);
      expect(r.liste.single.content, 'Oui');
    });
  });

  test('la liste montre « 👤 Jean », pas la fiche JSON', () {
    final conv = Conversation.fromJson({
      'id': 'fil',
      'isGroup': false,
      'title': 'Bob',
      'members': const [],
      'lastMessage': null,
      'unread': 0,
      'updatedAt': DateTime(2026, 10, 6).toIso8601String(),
      'e2eeActif': true,
    });
    final liste = appliquerDerniersTextes([conv], {
      'fil': LastMessage(
        id: 'neuf',
        content: _fiche,
        type: 'CONTACT',
        senderId: 'bob',
        createdAt: DateTime(2026, 10, 6, 10),
      ),
    });
    expect(liste.single.lastMessage?.content, '👤 Jean');
  });
}
