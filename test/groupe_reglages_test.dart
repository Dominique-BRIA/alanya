import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/models/conversation.dart';
import 'package:alanya/models/groupe_reglages.dart';

/// Les réglages d'un groupe et la sourdine détaillée (01/11/2026).
/// Lancer avec : flutter test test/groupe_reglages_test.dart
void main() {
  test('un serveur ancien : le fonctionnement d\'avant', () {
    final r = ReglagesGroupe.fromJson(null, null);
    expect(r.adminsSeulsEcrivent, isFalse);
    expect(r.adminsSeulsModifient, isTrue);
    expect(r.adminsSeulsAjoutent, isTrue);
    expect(r.historiqueCacheNouveaux, isFalse);
    expect(r.arriveeAConfirmer, isFalse);
    expect(r.proprietaireId, isNull);
  });

  test('les réglages se relisent depuis la copie du téléphone', () {
    final r = ReglagesGroupe.fromJson({
      'description': 'Équipe terrain',
      'proprietaireId': 'u1',
      'adminsSeulsEcrivent': true,
      'adminsSeulsModifient': false,
      'adminsSeulsAjoutent': false,
      'historiqueCacheNouveaux': true,
    }, {
      'arriveeAConfirmer': true,
    });
    final j = r.toJson();
    final relu = ReglagesGroupe.fromJson(
      (j['groupe'] as Map).cast<String, dynamic>(),
      (j['moi'] as Map).cast<String, dynamic>(),
    );
    expect(relu.description, 'Équipe terrain');
    expect(relu.proprietaireId, 'u1');
    expect(relu.adminsSeulsEcrivent, isTrue);
    expect(relu.adminsSeulsModifient, isFalse);
    expect(relu.adminsSeulsAjoutent, isFalse);
    expect(relu.historiqueCacheNouveaux, isTrue);
    expect(relu.arriveeAConfirmer, isTrue);

    // « Rester » efface la bannière, rien d'autre.
    final reste = relu.copyWith(arriveeAConfirmer: false);
    expect(reste.arriveeAConfirmer, isFalse);
    expect(reste.description, 'Équipe terrain');
    // Une description vidée s'efface.
    expect(relu.copyWith(effacerDescription: true).description, isNull);
  });

  test('la sourdine pour un temps et « mentions seulement »', () {
    final e = EtatSourdine.fromJson({
      'sourdine': true,
      'sourdineJusqua': '2026-11-01T20:00:00.000Z',
      'mentionsSeulement': true,
    });
    expect(e.sourdine, isTrue);
    expect(e.jusqua!.toUtc(), DateTime.utc(2026, 11, 1, 20));
    expect(e.mentionsSeulement, isTrue);

    final c = Conversation.fromJson({
      'id': 'c1',
      'isGroup': true,
      'title': 'Groupe',
      'members': const [],
      'unread': 0,
      'updatedAt': '2026-11-01T10:00:00.000Z',
      'sourdine': true,
      'sourdineJusqua': '2026-11-01T20:00:00.000Z',
      'mentionsSeulement': true,
      'arriveeAConfirmer': true,
    });
    expect(c.sourdineJusqua!.toUtc(), DateTime.utc(2026, 11, 1, 20));
    expect(c.mentionsSeulement, isTrue);
    expect(c.arriveeAConfirmer, isTrue);
    // Les copies gardent les nouveaux champs.
    final archivee = c.copieArchivee(true);
    expect(archivee.mentionsSeulement, isTrue);
    expect(archivee.arriveeAConfirmer, isTrue);
    final retablie =
        c.copieAvecEtatSourdine(sourdine: false, mentionsSeulement: false);
    expect(retablie.sourdine, isFalse);
    expect(retablie.sourdineJusqua, isNull);
  });
}
