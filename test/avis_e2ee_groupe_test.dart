// LES AVIS SYSTÈME DES GROUPES CHIFFRÉS (lot 7, chapitre 36).
//
// Le serveur dépose `{"code":"e2ee_active","actor":…}` et
// `{"code":"e2ee_cle_changee","actor":…}`. Ce test vérifie que le téléphone en
// fait une phrase, et qu'un code inconnu (serveur plus récent) ne montre rien
// plutôt qu'un JSON brut.

import 'dart:convert';

import 'package:alanya/core/locale_controller.dart';
import 'package:alanya/core/message_cache.dart' show estChargeTechnique;
import 'package:alanya/core/messages_systeme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<String> composer(WidgetTester tester, Map<String, String> charge) async {
    late String texte;
    await tester.pumpWidget(ChangeNotifierProvider<LocaleController>.value(
      value: LocaleController(),
      child: MaterialApp(
        home: Builder(builder: (context) {
          texte = composerMessageSysteme(context, jsonEncode(charge), 'moi');
          return const SizedBox();
        }),
      ),
    ));
    return texte;
  }

  testWidgets('« a activé le chiffrement de bout en bout »', (tester) async {
    expect(await composer(tester, {'code': 'e2ee_active', 'actor': 'Alice'}),
        'Alice a activé le chiffrement de bout en bout');
  });

  testWidgets('« a changé la clé du groupe »', (tester) async {
    expect(await composer(tester, {'code': 'e2ee_cle_changee', 'actor': 'Alice'}),
        'Alice a changé la clé du groupe');
  });

  testWidgets('un code inconnu : rien, jamais le JSON brut', (tester) async {
    expect(await composer(tester, {'code': 'code_du_futur', 'actor': 'Alice'}), '');
  });

  // Le cache ne range ni ne montre un trousseau comme un message (défaut de
  // l'ancienne application, constaté le 10/10/2026 : aperçu « G1{…} »).
  test("un trousseau ou une demande n'est jamais un message", () {
    expect(estChargeTechnique('\u0000G1{"v":1,"type":"trousseau"}'), isTrue);
    expect(estChargeTechnique('\u0000GD{"v":1,"type":"demande-trousseau"}'), isTrue);
    expect(estChargeTechnique('\u0000A2{"v":2,"id":"x","texte":"bonjour"}'), isFalse);
    expect(estChargeTechnique('G1 est un modèle de voiture'), isFalse);
    expect(estChargeTechnique(null), isFalse);
  });
}
