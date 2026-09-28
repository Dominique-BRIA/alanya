// CE QUE LA RELÈVE APPORTE À L'ÉCRAN — `fusionnerReleve`.
//
// 🐛 Signalé le 28/09/2026 : sur mobile, un message chiffré reçu pendant qu'on
// est DANS la conversation ne s'affichait pas ; il fallait la rouvrir. La
// relève ne faisait que remplir les bulles déjà affichées, et celle-ci n'y
// était pas : la route REST qui crée un message chiffré ne diffuse rien.

import 'package:alanya/features/chat/fusion_releve.dart';
import 'package:alanya/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

Message _bulle(String id, {String? texte, int minute = 0, String conv = 'fil'}) => Message(
      id: id,
      convId: conv,
      senderId: 'bob',
      content: texte,
      type: 'TEXT',
      status: 'DELIVERED',
      replyToId: null,
      media: const [],
      createdAt: DateTime(2026, 9, 28, 10, minute),
    );

({String id, String convId, String expediteurId, String texte, int quand}) _releve(
  String id, String texte, {int minute = 0, String conv = 'fil'}) =>
    (
      id: id,
      convId: conv,
      expediteurId: 'bob',
      texte: texte,
      quand: DateTime(2026, 9, 28, 10, minute).millisecondsSinceEpoch,
    );

void main() {
  test('un message relevé ABSENT de l’écran y est ajouté', () {
    final r = fusionnerReleve(
      [_bulle('ancien', texte: 'bonjour', minute: 1)],
      [_releve('neuf', 'ça va ?', minute: 2)],
      'fil',
    );
    expect(r.liste.map((m) => m.content), ['bonjour', 'ça va ?'],
        reason: 'le message n’apparaît qu’en rouvrant la conversation');
    expect(r.ajoutes.single.id, 'neuf');
    expect(r.ajoutes.single.senderId, 'bob');
  });

  test('une bulle déjà affichée, vide, reçoit son texte (sans doublon)', () {
    final r = fusionnerReleve([_bulle('m1')], [_releve('m1', 'texte')], 'fil');
    expect(r.liste.single.content, 'texte');
    expect(r.ajoutes, isEmpty);
  });

  // 🐛 L'enveloppe peut arriver APRÈS la suppression pour tous : la bulle,
  // vide parce que supprimée, recevait le texte du message supprimé.
  test('une bulle SUPPRIMÉE ne reçoit pas de texte', () {
    final supprimee = Message(
      id: 'm1',
      convId: 'fil',
      senderId: 'bob',
      content: null,
      type: 'TEXT',
      status: 'DELIVERED',
      replyToId: null,
      media: const [],
      createdAt: DateTime(2026, 9, 28, 10),
      deletedAt: DateTime(2026, 9, 28, 11),
    );
    final r = fusionnerReleve([supprimee], [_releve('m1', 'supprimé')], 'fil');
    expect(r.liste.single.content, isNull,
        reason: 'le texte d’un message supprimé pour tous revenait à l’écran');
    expect(r.ajoutes, isEmpty);
  });

  // 🐛 L'identifiant du message vient du serveur, hors du chiffré : un serveur
  // malveillant rattachait le texte de Bob à une bulle d'Alice. L'expéditeur,
  // lui, est sûr (c'est sa session qui déchiffre) : la bulle doit être la sienne.
  test('un texte relevé ne remplit pas la bulle d’un AUTRE expéditeur', () {
    final bulleAlice = Message(
      id: 'm1',
      convId: 'fil',
      senderId: 'alice',
      content: null,
      type: 'TEXT',
      status: 'SENT',
      replyToId: null,
      media: const [],
      createdAt: DateTime(2026, 9, 28, 10),
    );
    final r = fusionnerReleve([bulleAlice], [_releve('m1', 'mots de Bob')], 'fil');
    expect(r.liste.single.content, isNull,
        reason: 'le serveur a fait parler Alice avec les mots de Bob');
  });

  test('un texte relevé ne remplit pas une bulle d’un AUTRE fil', () {
    final r = fusionnerReleve([_bulle('m1', conv: 'fil')], [_releve('m1', 'ailleurs', conv: 'autre')], 'fil');
    expect(r.liste.single.content, isNull);
  });

  test('un texte déjà connu n’est jamais remplacé', () {
    final r = fusionnerReleve([_bulle('m1', texte: 'connu')], [_releve('m1', 'autre')], 'fil');
    expect(r.liste.single.content, 'connu');
  });

  test('les messages d’un AUTRE fil ne s’affichent pas ici', () {
    final r = fusionnerReleve([], [_releve('x', 'ailleurs', conv: 'autre')], 'fil');
    expect(r.liste, isEmpty);
  });

  test('l’ordre reste chronologique', () {
    final r = fusionnerReleve(
      [_bulle('b', texte: 'deux', minute: 2)],
      [_releve('a', 'un', minute: 1), _releve('c', 'trois', minute: 3)],
      'fil',
    );
    expect(r.liste.map((m) => m.content), ['un', 'deux', 'trois']);
  });
}
