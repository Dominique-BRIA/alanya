import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/core/alanya_id_formatter.dart';

/// Spécification exécutable du formatage de l'Alanya ID.
/// Lancer avec : flutter test test/alanya_id_formatter_test.dart
void main() {
  group('formatAlanyaId — longueurs prévues', () {
    test('3 chiffres : pas de découpage', () {
      expect(formatAlanyaId('123'), '123');
    });
    test('4 chiffres : 2 par 2', () {
      expect(formatAlanyaId('1234'), '12 34');
    });
    test('6 chiffres : 3 par 3', () {
      expect(formatAlanyaId('123456'), '123 456');
    });
    test('8 chiffres : 2 par 2 — le seul cas émis par le serveur', () {
      expect(formatAlanyaId('67641599'), '67 64 15 99');
    });
    test('10 chiffres : 1 puis 3 par 3', () {
      expect(formatAlanyaId('1234567890'), '1 234 567 890');
    });
  });

  group('formatAlanyaId — cas limites', () {
    test('longueur non prévue : repli sur un découpage 2 par 2', () {
      expect(formatAlanyaId('12345'), '12 34 5');
    });
    test('chaîne vide', () {
      expect(formatAlanyaId(''), '');
    });
    test('idempotent : reformater un ID déjà formaté ne change rien', () {
      for (final id in ['123', '1234', '123456', '67641599', '1234567890']) {
        final une = formatAlanyaId(id);
        expect(formatAlanyaId(une), une, reason: 'ID $id');
      }
    });
  });

  group('stripAlanyaId', () {
    test('retire les espaces', () {
      expect(stripAlanyaId('67 64 15 99'), '67641599');
      expect(stripAlanyaId('1 234 567 890'), '1234567890');
    });
    test('retire aussi tirets, points et espace insécable (copier-coller)', () {
      expect(stripAlanyaId('67-64-15-99'), '67641599');
      expect(stripAlanyaId('123.456'), '123456');
      expect(stripAlanyaId('67 64 15 99'), '67641599');
      expect(stripAlanyaId('(123) 456'), '123456');
    });
    test('un ID déjà brut est inchangé', () {
      expect(stripAlanyaId('12345678'), '12345678');
    });
    test('chaîne vide', () {
      expect(stripAlanyaId(''), '');
    });
  });

  test('aller-retour : format puis strip redonne les chiffres d\'origine', () {
    for (final id in ['123', '1234', '123456', '67641599', '1234567890']) {
      expect(stripAlanyaId(formatAlanyaId(id)), id);
    }
  });

  group('validation des saisies (règle serveur : 6 ou 8 chiffres)', () {
    final valide = RegExp(r'^(\d{6}|\d{8})$');

    test('un ID collé au format passe la validation après nettoyage', () {
      expect(valide.hasMatch(stripAlanyaId('67 64 15 99')), isTrue);
      expect(valide.hasMatch(stripAlanyaId('123 456')), isTrue);
    });
    test('sans nettoyage, le même ID serait refusé', () {
      expect(valide.hasMatch('67 64 15 99'), isFalse);
    });
    test('une longueur hors 6/8 reste refusée', () {
      expect(valide.hasMatch(stripAlanyaId('1234')), isFalse);
      expect(valide.hasMatch(stripAlanyaId('1 234 567 890')), isFalse);
    });
  });
}
