import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/widgets/biometric_gate.dart';

/// Quand redemander l'empreinte au retour dans l'application.
/// Lancer avec : flutter test test/verrou_empreinte_test.dart
void main() {
  final t0 = DateTime(2026, 10, 18, 12);

  test("jamais passée en arrière-plan : rien n'est redemandé", () {
    expect(empreinteExigeeAuRetour(quitteeA: null, maintenant: t0), isFalse);
  });

  test('galerie ou appareil photo, quelques secondes : rien', () {
    expect(
      empreinteExigeeAuRetour(
          quitteeA: t0, maintenant: t0.add(const Duration(seconds: 8))),
      isFalse,
    );
  });

  test('juste sous le délai : rien', () {
    expect(
      empreinteExigeeAuRetour(
          quitteeA: t0,
          maintenant: t0.add(delaiReverrouillage - const Duration(milliseconds: 1))),
      isFalse,
    );
  });

  test("au délai et au-delà : l'empreinte est redemandée", () {
    expect(
      empreinteExigeeAuRetour(quitteeA: t0, maintenant: t0.add(delaiReverrouillage)),
      isTrue,
    );
    expect(
      empreinteExigeeAuRetour(
          quitteeA: t0, maintenant: t0.add(const Duration(minutes: 10))),
      isTrue,
    );
  });

  test('le délai est de 30 secondes, comme Talky', () {
    expect(delaiReverrouillage, const Duration(seconds: 30));
  });
}
