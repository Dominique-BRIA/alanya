// UN MÉDIA CHIFFRÉ PAR LE VRAI CODE DU MOBILE, OUVERT PAR LE WEB (chapitre 25).
//
// La moitié mobile de `STAGE-WEB/scripts/e2ee-media-mobile-envoi.mjs` : le
// mobile chiffre une photo (`chiffrerFichier`), la téléverse marquée chiffrée,
// puis écrit la ligne du message et les enveloppes (`E2eeFil.envoyerMedia`).
// Le navigateur du correspondant doit l'afficher déchiffrée.
//
// ⚠️ IGNORÉ SANS SES VARIABLES. Variables : E2EE_API, E2EE_JETON, E2EE_MOI,
// E2EE_PAIR, E2EE_CONV, E2EE_PNG (chemin d'une image), E2EE_LEGENDE.

import 'dart:convert';
import 'dart:io';

import 'package:alanya/services/e2ee/e2ee_coffre.dart';
import 'package:alanya/services/e2ee/e2ee_fil.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:alanya/services/e2ee/e2ee_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final env = Platform.environment;
  final api = env['E2EE_API'];

  test(
    'le mobile envoie une photo chiffrée au web, par le vrai serveur',
    () async {
      HttpOverrides.global = null;
      FlutterSecureStorage.setMockInitialValues({});

      final jeton = env['E2EE_JETON']!;
      final moi = env['E2EE_MOI']!;
      final client = HttpClient();

      Future<Map<String, dynamic>> appel(
        String methode,
        String chemin,
        Map<String, dynamic>? corps,
      ) async {
        final req = await client.openUrl(methode, Uri.parse('$api$chemin'));
        req.headers.set('Authorization', 'Bearer $jeton');
        req.headers.contentType = ContentType.json;
        if (corps != null) req.write(jsonEncode(corps));
        final rep = await req.close();
        final texte = await rep.transform(utf8.decoder).join();
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

      final clair = File(env['E2EE_PNG']!).readAsBytesSync();
      final f = chiffrerFichier(clair);

      // Le téléversement, comme `MediaRepository.upload(chiffre: true)`.
      final envoi = http.MultipartRequest('POST', Uri.parse('$api/api/media'))
        ..headers['Authorization'] = 'Bearer $jeton'
        ..fields['chiffre'] = '1'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            f.chiffre,
            filename: 'chiffre.bin',
          ),
        );
      final rep = await http.Response.fromStream(await envoi.send());
      expect(rep.statusCode, lessThan(300), reason: rep.body);
      final mediaId = (jsonDecode(rep.body) as Map)['id'] as String;

      final d = DescripteurMedia(
        id: mediaId,
        cle: f.cle,
        empreinte: f.empreinte,
        taille: clair.length,
        mime: 'image/png',
        nom: 'du-telephone.png',
        largeur: 40,
        hauteur: 30,
      );
      final id = await fil.envoyerMedia(
        convId: env['E2EE_CONV']!,
        pairId: env['E2EE_PAIR']!,
        media: d,
        legende: env['E2EE_LEGENDE'] ?? '',
      );
      stdout.writeln('[mobile] ENVOYÉ : message $id, média $mediaId');
    },
    skip: api == null ? 'banc manuel : variables E2EE_* absentes' : false,
  );
}
