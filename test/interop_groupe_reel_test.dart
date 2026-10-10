// UN GROUPE CHIFFRÉ ENTRE LE MOBILE ET LE WEB, PAR LE VRAI SERVEUR — lot 8,
// cours chapitre 36.
//
// 🔴 La moitié mobile de `STAGE-WEB/scripts/e2ee-groupe-mobile-web.mjs`, qui
// l'orchestre : le vrai code de l'application (`CoffreE2ee`, `E2eeService`,
// `E2eeFil`, `GroupeChiffre`) en vraies requêtes HTTP vers un backend local,
// face à un navigateur qui fait tourner le vrai client web.
//
// Le scénario, côté mobile (administratrice) :
//   1. publier ses clés, ACTIVER le groupe (la clé part vers le navigateur) ;
//   2. écrire T1 ;
//   3. attendre la réponse du navigateur et la LIRE ;
//   4. CHANGER LA CLÉ, puis écrire T2 en version 2.
//
// ⚠️ IGNORÉ SANS SES VARIABLES : lancé seul, `flutter test` le saute.
// Variables : E2EE_API, E2EE_JETON, E2EE_MOI, E2EE_CONV, E2EE_T1, E2EE_T2,
// E2EE_WEB (le compte du navigateur).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('groupe chiffré : le mobile active, écrit, lit le web, change la clé', () async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});

    final jeton = env['E2EE_JETON']!;
    final moi = env['E2EE_MOI']!;
    final conv = env['E2EE_CONV']!;
    final web = env['E2EE_WEB']!;
    final client = HttpClient();

    Future<Map<String, dynamic>> appel(
        String methode, String chemin, Map<String, dynamic>? corps) async {
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

    void banc(String ligne) => stdout.writeln('BANC: $ligne');

    final coffre = CoffreE2ee(moi);
    await coffre.preparer();
    final service = E2eeService(coffre, appel);
    await service.publierMesCles(deviceId: await coffre.deviceId());
    final fil = E2eeFil(service, appel, coffre.deviceId, monCompte: moi);
    banc('CLES ${await coffre.deviceId()}');

    // 1. Activer : la clé 1 part vers chaque appareil du navigateur.
    final activation = await fil.groupe.activer(conv);
    banc('ACTIVE deja=${activation.deja} appareils=${activation.bilan?.appareils}');

    // 2. Écrire T1.
    final t1 = await fil.envoyer(convId: conv, pairId: null, texte: env['E2EE_T1']!);
    banc('ENVOYE_T1 $t1');

    // 2bis. Un FICHIER chiffré dans le groupe : téléversé chiffré, sa clé
    // voyage dans le chiffré de groupe (comme `MediaRepository.upload`).
    final contenu = utf8.encode(env['E2EE_FICHIER']!);
    final f = chiffrerFichier(Uint8List.fromList(contenu));
    final envoi = http.MultipartRequest('POST', Uri.parse('$api/api/media'))
      ..headers['Authorization'] = 'Bearer $jeton'
      ..fields['chiffre'] = '1'
      ..files.add(http.MultipartFile.fromBytes('file', f.chiffre, filename: 'chiffre.bin'));
    final repMedia = await http.Response.fromStream(await envoi.send());
    expect(repMedia.statusCode, lessThan(300), reason: repMedia.body);
    final mediaId = (jsonDecode(repMedia.body) as Map)['id'] as String;
    final idFichier = await fil.envoyerMedia(
      convId: conv,
      pairId: null,
      media: DescripteurMedia(
        id: mediaId,
        cle: f.cle,
        empreinte: f.empreinte,
        taille: contenu.length,
        mime: 'text/plain',
        nom: 'du-telephone.txt',
      ),
      legende: 'fichier du téléphone',
    );
    banc('ENVOYE_FICHIER $idFichier');

    // 3. Attendre la réponse du navigateur — un texte, puis un fichier — et
    // les lire. Le fichier est TÉLÉCHARGÉ chiffré, puis ouvert avec la clé
    // reçue dans le chiffré de groupe.
    String? lu;
    String? fichierLu;
    for (var i = 0; i < 90 && (lu == null || fichierLu == null); i++) {
      final page = await appel('GET', '/api/conversations/$conv/messages?limit=20', null);
      for (final m in ((page['messages'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        if (m['senderId'] != web || m['groupe'] == null) continue;
        final (clair, echec) = await fil.groupe.lire(
          convId: conv,
          messageId: m['id'] as String,
          expediteurId: web,
          chiffre: m['groupe'] as Map<String, dynamic>,
        );
        if (echec != null) banc('ECHEC_LECTURE $echec');
        if (clair == null) continue;
        final d = clair.media;
        if (d == null) {
          lu = clair.texte;
          continue;
        }
        final req = await client.getUrl(Uri.parse('$api/api/media/${d.id}'));
        req.headers.set('Authorization', 'Bearer $jeton');
        final rep = await req.close();
        final octets = await rep.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        final ouvert = dechiffrerFichier(Uint8List.fromList(octets),
            cle: d.cle, empreinte: d.empreinte, taille: d.taille);
        fichierLu = '${d.nom}|${utf8.decode(ouvert)}';
      }
      if (lu == null || fichierLu == null) await Future<void>.delayed(const Duration(seconds: 1));
    }
    banc('LU ${lu ?? "(rien)"}');
    banc('FICHIER_LU ${fichierLu ?? "(rien)"}');
    expect(lu, isNotNull, reason: 'le message du navigateur n\'a pas été lu');
    expect(fichierLu, isNotNull, reason: 'le fichier du navigateur n\'a pas été ouvert');

    // 4. Changer la clé, puis écrire T2 en version 2.
    final change = await fil.groupe.changerCle(conv, 'MANUEL');
    banc('CLE_CHANGEE ${change?.version}');
    final t2 = await fil.envoyer(convId: conv, pairId: null, texte: env['E2EE_T2']!);
    banc('ENVOYE_T2 $t2');
    banc('FINI');
    client.close();
  }, skip: api == null ? 'banc manuel : variables E2EE_* absentes' : false,
      timeout: const Timeout(Duration(minutes: 4)));
}
