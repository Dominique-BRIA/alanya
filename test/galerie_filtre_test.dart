import 'package:alanya/core/galerie.dart';
import 'package:flutter_test/flutter_test.dart';

/// LE FILTRE DE LA GALERIE DOIT RESTER LISIBLE PAR ANDROID (15/11/2026).
///
/// 🐛 Une durée de vidéo d'un an, en millisecondes, dépassait un entier 32
/// bits : le code Android de photo_manager la lit avec `as Int`, levait, et la
/// galerie entière restait vide. Toute valeur numérique envoyée par le filtre
/// doit tenir sur 32 bits.
void main() {
  const max32 = 2147483647;

  /// Toutes les valeurs numériques d'une carte, en profondeur.
  Iterable<num> nombres(Object? v) sync* {
    if (v is num) {
      yield v;
    } else if (v is Map) {
      for (final x in v.values) {
        yield* nombres(x);
      }
    } else if (v is List) {
      for (final x in v) {
        yield* nombres(x);
      }
    }
  }

  /// Ce qu'Android reçoit vraiment : les options sont sous `child`.
  Map enfant() => ordreRecentDAbord.toMap()['child'] as Map;

  test('la durée maximale des vidéos tient sur 32 bits', () {
    expect(dureeVideoMax.inMilliseconds, lessThanOrEqualTo(max32));
  });

  test('aucune valeur du filtre envoyé à Android ne dépasse 32 bits', () {
    final options = [enfant()['image'], enfant()['video'], enfant()['audio']];
    expect(options.whereType<Map>().length, 3, reason: 'options introuvables');
    // Le défaut : une durée d'un an en millisecondes serait ici, et ferait
    // échouer la requête Android.
    for (final n in nombres(options)) {
      expect(n.abs(), lessThanOrEqualTo(max32), reason: 'valeur trop grande : $n');
    }
  });

  test('la taille est ignorée pour les images et les vidéos', () {
    expect((enfant()['image'] as Map)['size']['ignoreSize'], isTrue);
    expect((enfant()['video'] as Map)['size']['ignoreSize'], isTrue);
  });

  test('une vidéo sans durée connue est acceptée', () {
    expect((enfant()['video'] as Map)['duration']['allowNullable'], isTrue);
  });
}
