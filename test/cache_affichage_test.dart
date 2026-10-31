import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/models/message.dart';

/// Ce que le cache des messages garde depuis la v9 (01/11/2026) : la citation
/// d'un statut, les réactions, les boutons. Chacun doit se relire tel qu'il a
/// été écrit. Lancer avec : flutter test test/cache_affichage_test.dart
void main() {
  test('la citation d\'un statut se relit à l\'identique', () {
    final c = StatutCite(
      statusId: 's1',
      authorId: 'u1',
      type: 'AUDIO',
      mediaUrl: '/api/media/m1',
    );
    final relue = StatutCite.fromJson(c.toJson());
    expect(relue.statusId, 's1');
    expect(relue.authorId, 'u1');
    expect(relue.type, 'AUDIO');
    expect(relue.text, isNull);
    expect(relue.mediaUrl, '/api/media/m1');
    expect(relue.apercu, 'Audio');
  });

  test('une réaction et un bouton se relisent à l\'identique', () {
    final r = MessageReaction.fromJson(MessageReaction(userId: 'u2', emoji: '👍').toJson());
    expect(r.userId, 'u2');
    expect(r.emoji, '👍');

    final b = BoutonMessage.fromJson(
        const BoutonMessage(label: 'Aide', action: 'route', target: 'help').toJson());
    expect(b.label, 'Aide');
    expect(b.estLien, isFalse);
    expect(b.target, 'help');
  });
}
