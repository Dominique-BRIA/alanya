// LE VRAI CODE DE CHIFFREMENT DU MOBILE, CONTRE LE VRAI SERVEUR.
//
// 🔴 POURQUOI CE TEST. Les autres tests E2EE du mobile parlent à un FAUX
// serveur. Celui-ci fait tourner `CoffreE2ee`, `E2eeService` et `E2eeFil` —
// exactement le code de l'application — en vraies requêtes HTTP vers un
// backend local, pour qu'un navigateur (le client web) déchiffre ensuite.
// C'est la moitié mobile de `STAGE-WEB/scripts/e2ee-mobile-web.mjs`, qui
// l'orchestre.
//
// ⚠️ IGNORÉ SANS SES VARIABLES : lancé seul, `flutter test` le saute.
//
// Variables : E2EE_API, E2EE_JETON, E2EE_MOI, E2EE_PAIR, E2EE_CONV, E2EE_TEXTE.

import 'dart:convert';
import 'dart:io';

import 'package:alanya/services/e2ee/e2ee_coffre.dart';
import 'package:alanya/services/e2ee/e2ee_fil.dart';
import 'package:alanya/services/e2ee/e2ee_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  final api = env['E2EE_API'];

  test('le mobile chiffre un message pour le web, par le vrai serveur', () async {
    // ⚠️ Le banc de test Flutter peut bloquer le réseau : on le rétablit.
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});

    final jeton = env['E2EE_JETON']!;
    final moi = env['E2EE_MOI']!;
    final client = HttpClient();

    Future<Map<String, dynamic>> appel(
        String methode, String chemin, Map<String, dynamic>? corps) async {
      final req = await client.openUrl(methode, Uri.parse('$api$chemin'));
      req.headers.set('Authorization', 'Bearer $jeton');
      req.headers.contentType = ContentType.json;
      if (corps != null) req.write(jsonEncode(corps));
      final rep = await req.close();
      final texte = await rep.transform(utf8.decoder).join();
      stdout.writeln('[http] $methode $chemin → ${rep.statusCode}');
      if (rep.statusCode >= 400) {
        throw HttpException('$methode $chemin → ${rep.statusCode} $texte');
      }
      final json = texte.isEmpty ? <String, dynamic>{} : jsonDecode(texte);
      return json is Map<String, dynamic> ? json : {'donnees': json};
    }

    final coffre = CoffreE2ee(moi);
    await coffre.preparer();
    final service = E2eeService(coffre, appel);
    await service.publierMesCles(deviceId: await coffre.deviceId());
    final fil = E2eeFil(service, appel, coffre.deviceId, monCompte: moi);

    final id = await fil.envoyer(
      convId: env['E2EE_CONV']!,
      pairId: env['E2EE_PAIR']!,
      texte: env['E2EE_TEXTE']!,
    );
    stdout.writeln('ENVOYE $id DEVICE ${await coffre.deviceId()}');
    client.close();
  }, skip: api == null ? 'banc manuel : variables E2EE_* absentes' : false);
}
