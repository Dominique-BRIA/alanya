import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/core/nom_personne.dart';

/// Mêmes cas que le contrôle du serveur (`src/lib/validation.ts`).
void main() {
  const acceptes = ['Jean', 'Li', '王伟', 'J1', 'Ngo   Bria '];
  const refuses = ['', '  ', '..', '--', 'a.', 'É', '😀😀', 'ㅤㅤ', '​​', '⠀⠀'];

  for (final n in acceptes) {
    test('accepte « $n »', () => expect(nomPersonneValide(n), isTrue));
  }
  for (final n in refuses) {
    test('refuse « $n »', () => expect(nomPersonneValide(n), isFalse));
  }
  test('nettoie les espaces et les invisibles', () {
    expect(nettoyerNom(' Ngo  ​ Bria '), 'Ngo Bria');
  });
}
