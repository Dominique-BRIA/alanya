import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/models/message.dart';

void main() {
  Map<String, dynamic> base([Map<String, dynamic>? extra]) => {
    'id': 'm1',
    'convId': 'c1',
    'senderId': 'officiel',
    'content': 'Découvrir : https://alanyavox.com',
    'type': 'TEXT',
    'createdAt': '2026-10-24T12:00:00Z',
    ...?extra,
  };

  test('un message ordinaire n\'a pas de boutons', () {
    expect(Message.fromJson(base()).boutons, isEmpty);
  });

  test('les boutons sont lus, lien et écran', () {
    final m = Message.fromJson(
      base({
        'boutons': [
          {
            'label': 'Découvrir',
            'action': 'url',
            'target': 'https://alanyavox.com',
          },
          {'label': 'Mon profil', 'action': 'route', 'target': 'profile'},
        ],
      }),
    );
    expect(m.boutons, hasLength(2));
    expect(m.boutons.first.estLien, isTrue);
    expect(m.boutons.last.estLien, isFalse);
    expect(m.boutons.last.target, 'profile');
  });

  test('un bouton sans libellé ou sans cible est écarté', () {
    final m = Message.fromJson(
      base({
        'boutons': [
          {'label': '', 'action': 'url', 'target': 'https://alanyavox.com'},
          {'label': 'Profil', 'action': 'route', 'target': ''},
          'pas un objet',
        ],
      }),
    );
    expect(m.boutons, isEmpty);
  });

  test('les copies gardent les boutons', () {
    final m = Message.fromJson(
      base({
        'boutons': [
          {'label': 'Statuts', 'action': 'route', 'target': 'statuses'},
        ],
      }),
    );
    expect(m.avecStatut('READ').boutons, hasLength(1));
    expect(m.avecVueUnique(ouverte: true).boutons, hasLength(1));
    expect(m.avecDechiffre(texte: 'x').boutons, hasLength(1));
  });
}
