import 'package:alanya/features/calls/detecteur_parole.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DetecteurParole nouveau() => DetecteurParole(onChange: () {});

  test("il faut deux mesures au-dessus du seuil pour s'allumer", () {
    final d = nouveau();
    expect(d.mesurer('a', 0.3), isFalse);
    expect(d.parle('a'), isFalse);
    expect(d.mesurer('a', 0.3), isTrue);
    expect(d.parle('a'), isTrue);
  });

  test("un bruit isolé n'allume rien", () {
    final d = nouveau();
    d.mesurer('a', 0.3);
    d.mesurer('a', 0.01);
    d.mesurer('a', 0.3);
    expect(d.parle('a'), isFalse);
  });

  test("quatre mesures de silence pour s'éteindre, pas moins", () {
    final d = nouveau();
    d.mesurer('a', 0.3);
    d.mesurer('a', 0.3);
    for (var i = 0; i < 3; i++) {
      expect(d.mesurer('a', 0.0), isFalse);
    }
    expect(d.parle('a'), isTrue);
    expect(d.mesurer('a', 0.0), isTrue);
    expect(d.parle('a'), isFalse);
  });

  test("chaque participant a ses propres compteurs", () {
    final d = nouveau();
    d.mesurer('a', 0.3);
    d.mesurer('b', 0.3);
    d.mesurer('a', 0.3);
    expect(d.parlent, {'a'});
  });
}
