import 'package:alanya/features/signalement/signalement_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// SIGNALER (18/11/2026, exigence du Play Store) : ce qui part au serveur.
void main() {
  test('message chiffré : son texte part avec le signalement', () {
    final c = SignalementSheet.corps(
      const SignalerMessage(messageId: 'm1', chiffre: true, extrait: 'bonjour'),
      'harassment',
      '',
    );
    expect(c, {'motif': 'harassment', 'cible': 'message', 'messageId': 'm1', 'extrait': 'bonjour'});
  });

  test('message en clair : pas d’extrait, le serveur le lit lui-même', () {
    final c = SignalementSheet.corps(
      const SignalerMessage(messageId: 'm1', chiffre: false, extrait: 'bonjour'),
      'spam',
      '',
    );
    expect(c.containsKey('extrait'), isFalse);
  });

  test('compte, groupe et réponse de l’Assistant', () {
    expect(SignalementSheet.corps(const SignalerCompte(userId: 'u1'), 'scam', ''),
        {'motif': 'scam', 'cible': 'user', 'userId': 'u1'});
    expect(SignalementSheet.corps(const SignalerGroupe('g1'), 'hate', ''),
        {'motif': 'hate', 'cible': 'group', 'convId': 'g1'});
    expect(SignalementSheet.corps(const SignalerReponseIa('a1'), 'other', ''),
        {'motif': 'other', 'cible': 'ia', 'aiMessageId': 'a1'});
  });

  test('la précision est nettoyée et bornée à 1 000 caractères', () {
    final c = SignalementSheet.corps(const SignalerGroupe('g1'), 'other', '  ${'x' * 1500}  ');
    expect((c['note'] as String).length, 1000);
    expect(SignalementSheet.corps(const SignalerGroupe('g1'), 'other', '   ').containsKey('note'), isFalse);
  });

  test('les motifs sont ceux du serveur', () {
    expect(SignalementSheet.motifs,
        ['harassment', 'hate', 'violence', 'sexual', 'scam', 'spam', 'impersonation', 'other']);
  });
}
