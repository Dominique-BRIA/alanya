// L'ÉTAT D'UN MESSAGE ENVOYÉ NE REDESCEND JAMAIS — `statut_envoi.dart`.
//
// Défaut signalé le 28/09/2026 : un « lu » reçu pendant l'envoi était effacé
// par la réponse du serveur, qui remettait la bulle « envoyé ».

import 'package:alanya/features/chat/statut_envoi.dart';
import 'package:alanya/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '« lu » reçu pendant l’envoi, puis la réponse « envoyé » : reste lu',
    () {
      expect(statutFusionne(affiche: 'READ', recu: 'SENT'), 'READ');
    },
  );

  test('« distribué » n’est pas effacé par « envoyé »', () {
    expect(statutFusionne(affiche: 'DELIVERED', recu: 'SENT'), 'DELIVERED');
  });

  test('en attente → envoyé : la réponse s’applique', () {
    expect(statutFusionne(affiche: 'PENDING', recu: 'SENT'), 'SENT');
  });

  test('le serveur sait plus : il gagne', () {
    expect(statutFusionne(affiche: 'PENDING', recu: 'DELIVERED'), 'DELIVERED');
    expect(statutFusionne(affiche: 'DELIVERED', recu: 'READ'), 'READ');
  });

  test('avecStatut garde tout le reste', () {
    final m = Message(
      id: 'a',
      convId: 'c',
      senderId: 'moi',
      content: 'salut',
      type: 'TEXT',
      status: 'SENT',
      replyToId: null,
      media: const [],
      createdAt: DateTime.utc(2026, 9, 28),
      chiffre: true,
    );
    final lu = m.avecStatut('READ');
    expect(lu.status, 'READ');
    expect(lu.content, 'salut');
    expect(lu.chiffre, isTrue, reason: 'la bande « chiffré » en dépend');
    expect(identical(m.avecStatut('SENT'), m), isTrue);
  });
}
