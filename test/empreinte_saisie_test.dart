import 'package:alanya/core/empreinte_saisie.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'empreinte se lit et se saisit en huit blocs de quatre (24/10/2026).
void main() {
  const code = '3f9a0c1e5b7d2a4c6e8f0a1b2c3d4e5f';

  test('affichage en blocs, en majuscules', () {
    expect(Empreinte.enBlocs(code), '3F9A 0C1E 5B7D 2A4C 6E8F 0A1B 2C3D 4E5F');
    expect(Empreinte.enBlocs('3f9a0'), '3F9A 0');
    expect(Empreinte.enBlocs(''), '');
  });

  test('un collage quelconque redevient une empreinte', () {
    expect(
      Empreinte.pourServeur(' 3F9A-0C1E 5b7d\n2A4C 6E8F 0A1B 2C3D 4E5F '),
      code,
    );
    // Trop court, ou des caractères hors de 0-9 A-F qui manquent ensuite.
    expect(Empreinte.pourServeur('3F9A 0C1E'), isNull);
    expect(Empreinte.nettoyer('3G9Z'), '39');
  });

  group('saisie', () {
    final f = FormateurEmpreinte();
    TextEditingValue taper(String avant, String apres, int curseur) =>
        f.formatEditUpdate(
          TextEditingValue(text: avant),
          TextEditingValue(
            text: apres,
            selection: TextSelection.collapsed(offset: curseur),
          ),
        );

    test('le 5e caractère ouvre un nouveau bloc, le curseur le suit', () {
      final v = taper('3F9A', '3F9A0', 5);
      expect(v.text, '3F9A 0');
      expect(v.selection.end, 6);
    });

    test('minuscules et séparateurs tapés sont corrigés', () {
      final v = taper('', 'ab-cd ef', 8);
      expect(v.text, 'ABCD EF');
      expect(v.selection.end, 7);
    });

    test('coller une empreinte entière la met en blocs', () {
      final v = taper('', code, code.length);
      expect(v.text, '3F9A 0C1E 5B7D 2A4C 6E8F 0A1B 2C3D 4E5F');
      expect(v.selection.end, v.text.length);
    });

    test('au-delà de 32 caractères, rien ne s’ajoute', () {
      final plein = Empreinte.enBlocs(code);
      final v = taper(plein, '${plein}9', plein.length + 1);
      expect(v.text, plein);
    });

    test('effacer au milieu garde le curseur au bon endroit', () {
      // « 3F9A 0C1E » : on efface le « 0 » (curseur juste après lui).
      final v = taper('3F9A 0C1E', '3F9A C1E', 5);
      expect(v.text, '3F9A C1E');
      expect(v.selection.end, 4);
    });
  });
}
