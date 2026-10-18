import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alanya/core/noms_donnes.dart';
import 'package:alanya/models/call_record.dart';
import 'package:alanya/models/contact.dart';
import 'package:alanya/models/conversation.dart';

/// Le nom que je donne à un contact s'affiche partout chez moi.
/// Lancer avec : flutter test test/noms_donnes_test.dart
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NomsDonnes.poserPourTest({'awa': 'Tata Awa'});
  });

  Conversation conv({required bool groupe, String? titre}) => Conversation(
        id: 'c1',
        isGroup: groupe,
        title: titre,
        avatarUrl: null,
        members: [
          ConvMember(id: 'moi', pseudo: 'Moi', publicNumber: '11111111'),
          ConvMember(id: 'awa', pseudo: 'Awa Ngono', publicNumber: '22222222'),
          ConvMember(id: 'paul', pseudo: 'Paul', publicNumber: '33333333'),
        ],
        lastMessage: null,
        unread: 0,
        updatedAt: DateTime(2026, 10, 18),
      );

  test("le nom donné passe devant le nom du profil, sinon le profil", () {
    expect(NomsDonnes.nomPour('awa', 'Awa Ngono'), 'Tata Awa');
    expect(NomsDonnes.nomPour('paul', 'Paul'), 'Paul');
    expect(NomsDonnes.nomPour(null, 'Inconnu'), 'Inconnu');
  });

  test('tête-à-tête : le titre devient le nom donné', () {
    final c = Conversation(
      id: 'c2',
      isGroup: false,
      title: 'Awa Ngono',
      avatarUrl: null,
      members: [
        ConvMember(id: 'moi', pseudo: 'Moi', publicNumber: '11111111'),
        ConvMember(id: 'awa', pseudo: 'Awa Ngono', publicNumber: '22222222'),
      ],
      lastMessage: null,
      unread: 0,
      updatedAt: DateTime(2026, 10, 18),
    );
    expect(c.titreAffiche('moi'), 'Tata Awa');
  });

  test('groupe : le titre reste celui du groupe, les membres prennent le nom donné', () {
    final c = conv(groupe: true, titre: 'Famille');
    expect(c.titreAffiche('moi'), 'Famille');
    expect(c.memberNames['awa'], 'Tata Awa');
    expect(c.memberNames['paul'], 'Paul');
  });

  test("journal d'appels : le nom donné, entrant comme sortant", () {
    CallRecord appel({required bool sortant, String? peerId, String? callerId}) =>
        CallRecord(
          id: 'a1',
          convId: 'c2',
          type: 'AUDIO',
          status: 'ENDED',
          isOutgoing: sortant,
          isGroup: false,
          peerName: 'Awa Ngono',
          peerNumber: '22222222',
          peerAvatarUrl: null,
          participantCount: 2,
          startedAt: DateTime(2026, 10, 18),
          answeredAt: null,
          endedAt: null,
          durationSec: null,
          peerId: peerId,
          callerId: callerId,
        );
    expect(appel(sortant: true, peerId: 'awa').nomAffiche, 'Tata Awa');
    expect(appel(sortant: false, peerId: 'awa', callerId: 'awa').nomAffiche, 'Tata Awa');
    // Serveur plus ancien, sans peerId : un appel reçu se rattache à l'appelant.
    expect(appel(sortant: false, callerId: 'awa').nomAffiche, 'Tata Awa');
    // Sortant sans peerId : on ne devine pas, le nom du serveur reste.
    expect(appel(sortant: true).nomAffiche, 'Awa Ngono');
  });

  test('la liste des contacts du serveur fait foi', () async {
    await NomsDonnes.depuisContacts([
      Contact(
        id: 'p1',
        alias: 'Papa',
        isBlocked: false,
        userId: 'paul',
        publicNumber: '33333333',
        pseudo: 'Paul',
        avatarUrl: null,
      ),
    ]);
    expect(NomsDonnes.de('paul'), 'Papa');
    // Awa n'a plus de nom donné côté serveur (ou elle l'a verrouillé).
    expect(NomsDonnes.de('awa'), isNull);
  });

  test('poser puis retirer un nom', () async {
    await NomsDonnes.poser('paul', '  Le voisin ');
    expect(NomsDonnes.de('paul'), 'Le voisin');
    await NomsDonnes.poser('paul', '');
    expect(NomsDonnes.de('paul'), isNull);
  });
}
