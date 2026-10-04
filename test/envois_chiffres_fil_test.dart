// LA BULLE D'UN MÉDIA CHIFFRÉ EN COURS D'ENVOI NE SE PERD PLUS.
//
// 🐛 « Quand j'envoie un PDF, il ne s'affiche pas chez moi ; il faut rouvrir la
// conversation » (user, 04/10/2026). Le relais `_poll` remplaçait la liste par
// la page du serveur, sans la bulle d'attente ; la fin de l'envoi ne trouvait
// alors plus rien à remplacer. Voir `envois_chiffres_fil.dart`.

import 'package:alanya/features/chat/envois_chiffres_fil.dart';
import 'package:alanya/models/message.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _pdf = DescripteurMedia(
  id: 'media-1',
  cle: 'AAAA',
  empreinte: 'AAAA',
  taille: 10,
  mime: 'application/pdf',
  nom: 'devis.pdf',
);

Message _msg(String id, {int minute = 0, String status = 'SENT', DescripteurMedia? d}) =>
    Message(
      id: id,
      convId: 'fil',
      senderId: 'moi',
      content: '',
      type: 'FILE',
      status: status,
      replyToId: null,
      media: const [],
      createdAt: DateTime.utc(2026, 10, 4, 12, minute),
      chiffre: true,
      mediaChiffre: d,
    );

void main() {
  group('garderEnvoisEnCours (relais _poll)', () {
    test("la bulle d'attente survit à la page du serveur", () {
      final serveur = [_msg('a'), _msg('b', minute: 1)];
      final affiches = [_msg('a'), _msg('b', minute: 1), _msg('tmp-1', minute: 2, status: 'PENDING')];

      final liste = garderEnvoisEnCours(serveur, affiches, {'tmp-1'});

      expect(liste.map((m) => m.id), ['a', 'b', 'tmp-1']);
    });

    test("une bulle dont l'envoi est fini n'est pas gardée", () {
      final serveur = [_msg('a')];
      final affiches = [_msg('a'), _msg('tmp-1', status: 'PENDING')];

      expect(garderEnvoisEnCours(serveur, affiches, const {}).map((m) => m.id), ['a']);
    });
  });

  group('remplacerEnvoiChiffre (fin de l’envoi)', () {
    test('la bulle d’attente est remplacée à sa place', () {
      final envoye = _msg('m-1', minute: 2, d: _pdf);
      final liste = remplacerEnvoiChiffre(
        [_msg('a'), _msg('tmp-1', minute: 2, status: 'PENDING')],
        'tmp-1',
        envoye,
      );

      expect(liste.map((m) => m.id), ['a', 'm-1']);
      expect(liste.last.mediaChiffre?.nom, 'devis.pdf');
    });

    test('LE DÉFAUT : bulle d’attente disparue, le message est AJOUTÉ quand même', () {
      final envoye = _msg('m-1', minute: 2, d: _pdf);
      final liste = remplacerEnvoiChiffre([_msg('a')], 'tmp-1', envoye);

      expect(liste.map((m) => m.id), ['a', 'm-1']);
    });

    test('la version du serveur, sans descripteur, cède la place', () {
      final envoye = _msg('m-1', minute: 2, d: _pdf);
      final liste = remplacerEnvoiChiffre(
        [_msg('a'), _msg('m-1', minute: 2), _msg('tmp-1', minute: 2, status: 'PENDING')],
        'tmp-1',
        envoye,
      );

      expect(liste.map((m) => m.id), ['a', 'm-1']);
      expect(liste.singleWhere((m) => m.id == 'm-1').mediaChiffre, isNotNull);
    });
  });
}
