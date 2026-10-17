// UN MÉDIA CHIFFRÉ PAR LE WEB, OUVERT PAR LE VRAI CODE DU MOBILE (chapitre 23).
//
// La moitié mobile de `STAGE-WEB/scripts/e2ee-media-mobile.mjs`, qui
// l'orchestre : le mobile publie ses clés, signale qu'il est prêt, le web lui
// envoie une photo chiffrée, et le mobile doit la relever, télécharger le
// fichier illisible du serveur, vérifier son empreinte et le déchiffrer.
//
// ⚠️ IGNORÉ SANS SES VARIABLES : lancé seul, `flutter test` le saute.
// Variables : E2EE_API, E2EE_JETON, E2EE_MOI, E2EE_PRET (fichier témoin).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_coffre.dart';
import 'package:alanya/services/e2ee/e2ee_fil.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:alanya/services/e2ee/e2ee_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  final api = env['E2EE_API'];

  test(
    'le mobile relève, télécharge et déchiffre une photo envoyée par le web',
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

      // Prêt : le web peut chiffrer pour cet appareil.
      File(env['E2EE_PRET']!).writeAsStringSync('pret');

      MessageClair? recu;
      for (var i = 0; i < 60 && recu == null; i++) {
        final r = await fil.relever();
        for (final m in r.messages) {
          if (m.media != null) recu = m;
        }
        if (recu == null)
          await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(recu, isNotNull, reason: 'aucune enveloppe portant un média');
      final d = recu!.media!;
      stdout.writeln(
        '[mobile] relevé : « ${recu.texte} », ${d.mime}, ${d.largeur}×${d.hauteur}',
      );

      // Le fichier du serveur : illisible tel quel.
      final req = await client.getUrl(
        Uri.parse('$api/api/media/${d.id}?token=$jeton'),
      );
      final rep = await req.close();
      final octets = BytesBuilder();
      await rep.forEach(octets.add);
      final chiffre = octets.takeBytes();
      expect(rep.statusCode, 200);
      const png = [137, 80, 78, 71, 13, 10, 26, 10];
      expect(
        List.generate(8, (i) => chiffre[i]),
        isNot(png),
        reason: 'le serveur ne doit stocker qu’un fichier illisible',
      );

      final clair = dechiffrerFichier(
        chiffre,
        cle: d.cle,
        empreinte: d.empreinte,
        taille: d.taille,
      );
      expect(
        List.generate(8, (i) => clair[i]),
        png,
        reason: 'le clair est un PNG',
      );
      expect(clair.length, d.taille);
      stdout.writeln('[mobile] DÉCHIFFRÉ : ${clair.length} octets, PNG valide');

      // Le même fichier, annoncé avec une autre empreinte : refusé.
      expect(
        () => dechiffrerFichier(
          chiffre,
          cle: d.cle,
          empreinte: base64Encode(Uint8List(32)),
          taille: d.taille,
        ),
        throwsA(isA<FichierInvalide>()),
      );
    },
    skip: api == null ? 'banc manuel : variables E2EE_* absentes' : false,
  );
}
