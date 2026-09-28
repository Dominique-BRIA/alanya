import 'package:alanya/core/avec_reprises.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _sansAttendre(Duration _) async {}

void main() {
  test('deux échecs puis un succès : trois essais, et le résultat', () async {
    var appels = 0;
    final r = await avecReprises(() async {
      appels++;
      if (appels < 3) throw Exception('réseau pas encore revenu');
      return 'relevé';
    }, attendre: _sansAttendre);
    expect(r, 'relevé');
    expect(appels, 3);
  });

  test(
    'toujours en échec : quatre essais au plus, puis null, sans lever',
    () async {
      var appels = 0;
      final r = await avecReprises<String>(() async {
        appels++;
        throw Exception('hors ligne');
      }, attendre: _sansAttendre);
      expect(r, isNull);
      expect(appels, 4);
    },
  );

  test('l’écran est fermé entre deux essais : on s’arrête', () async {
    var appels = 0;
    var ouvert = true;
    final r = await avecReprises<String>(
      () async {
        appels++;
        ouvert = false;
        throw Exception('hors ligne');
      },
      attendre: _sansAttendre,
      continuer: () => ouvert,
    );
    expect(r, isNull);
    expect(appels, 1);
  });

  test('succès au premier essai : aucune attente', () async {
    var attentes = 0;
    final r = await avecReprises(
      () async => 42,
      attendre: (_) async => attentes++,
    );
    expect(r, 42);
    expect(attentes, 0);
  });
}
