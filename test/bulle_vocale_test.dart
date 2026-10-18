import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/core/formes_onde_commun.dart';
import 'package:alanya/widgets/media/forme_onde_vocale.dart';

/// La forme d'onde des messages vocaux.
/// Lancer avec : flutter test test/bulle_vocale_test.dart
void main() {
  group("barres d'attente", () {
    test('jamais vides, toujours entre 0,08 et 1', () {
      final b = formeOndeDeRepli('msg-1', 12);
      expect(b, hasLength(barresFormeOnde));
      expect(b.every((v) => v >= 0.08 && v <= 1.0), isTrue);
    });

    test('la même forme pour le même vocal, une autre pour un autre', () {
      expect(formeOndeDeRepli('msg-1', 12), formeOndeDeRepli('msg-1', 12));
      expect(formeOndeDeRepli('msg-1', 12), isNot(formeOndeDeRepli('msg-2', 12)));
    });
  });

  testWidgets("un toucher sur l'onde avance à l'endroit touché", (t) async {
    double? touche;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: FormeOndeVocale(
              barres: formeOndeDeRepli('msg-1', 12),
              progression: 0.25,
              couleur: Colors.teal,
              onAvance: (r) => touche = r,
            ),
          ),
        ),
      ),
    ));
    final boite = t.getRect(find.byType(FormeOndeVocale));
    await t.tapAt(Offset(boite.left + boite.width * 0.75, boite.center.dy));
    expect(touche, closeTo(0.75, 0.02));
  });
}
