import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';

/// Le caractère « sensible » d'un document voyage dans l'enveloppe chiffrée.
/// Lancer avec : flutter test test/document_sensible_test.dart
void main() {
  final cle = base64Encode(List<int>.filled(32, 1));
  final empreinte = base64Encode(List<int>.filled(32, 2));

  DescripteurMedia descripteur({bool sensible = false}) => DescripteurMedia(
        id: 'media-1',
        cle: cle,
        empreinte: empreinte,
        taille: 1234,
        mime: 'application/pdf',
        nom: 'contrat.pdf',
        sensible: sensible,
      );

  test('un document sensible le reste après aller-retour', () {
    final relu = DescripteurMedia.depuisJson(
        jsonDecode(jsonEncode(descripteur(sensible: true).toJson())));
    expect(relu.sensible, isTrue);
  });

  test("un document ordinaire n'écrit pas le champ (format partagé avec le web)", () {
    final json = descripteur().toJson();
    expect(json.containsKey('sensible'), isFalse);
    expect(DescripteurMedia.depuisJson(json).sensible, isFalse);
  });

  test("un ancien descripteur, sans le champ, n'est pas sensible", () {
    final ancien = {
      'id': 'media-1',
      'cle': cle,
      'empreinte': empreinte,
      'taille': 10,
      'mime': 'application/pdf',
    };
    expect(DescripteurMedia.depuisJson(ancien).sensible, isFalse);
  });
}
