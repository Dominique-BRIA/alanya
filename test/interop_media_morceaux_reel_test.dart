// UN MÉDIA CHIFFRÉ ENVOYÉ EN MORCEAUX PAR LE VRAI CODE DU MOBILE, PUBLIÉ PAR
// LE SERVEUR, OUVERT PAR LE WEB (cours, chapitre 44).
//
// La moitié mobile de `STAGE-WEB/scripts/e2ee-media-morceaux-mobile.mjs`, qui
// l'orchestre. Le vrai `SuiviEnvoisMorceaux.lancer` : chiffrement de fichier à
// fichier, réservation, préparation des enveloppes, programmation de la
// publication, puis les morceaux — poussés ici par `TransportDirect` (en
// HTTP), là où l'application les confie à Android. Le message n'est JAMAIS
// posté par le mobile : c'est le serveur qui le publie au dernier morceau.
//
// ⚠️ IGNORÉ SANS SES VARIABLES. Variables : E2EE_API, E2EE_JETON, E2EE_MOI,
// E2EE_PAIR, E2EE_CONV, E2EE_PNG (chemin d'une image), E2EE_LEGENDE.
import 'dart:io';

import 'package:alanya/core/api_client.dart';
import 'package:alanya/core/authed_api.dart';
import 'package:alanya/core/token_storage.dart';
import 'package:alanya/features/chat/envoi_morceaux/envoi_morceaux_api.dart';
import 'package:alanya/features/chat/envoi_morceaux/envoi_morceaux_chiffre.dart';
import 'package:alanya/features/chat/envoi_morceaux/transport_morceaux.dart';
import 'package:alanya/models/message.dart';
import 'package:alanya/services/e2ee/e2ee_apercus.dart';
import 'package:alanya/services/e2ee/e2ee_coffre.dart';
import 'package:alanya/services/e2ee/e2ee_fil.dart';
import 'package:alanya/services/e2ee/e2ee_service.dart';
import 'package:alanya/widgets/media/media_picker_sheet.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

/// Le jeton du banc, sans stockage sécurisé.
class _Jetons extends TokenStorage {
  _Jetons(this._jeton);
  final String _jeton;
  @override
  Future<String?> get accessToken async => _jeton;
  @override
  Future<String?> get refreshToken async => null;
}

void main() {
  final env = Platform.environment;
  final api = env['E2EE_API'];

  test(
    'le mobile envoie une photo chiffrée EN MORCEAUX, le serveur la publie',
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

      final racine = Directory.systemTemp.createTempSync('morceaux_');
      final suivi = SuiviEnvoisMorceaux.instance
        ..brancher(
          api: EnvoiMorceauxApi(AuthedApi(ApiClient(baseUrl: api), _Jetons(jeton)), base: api),
          transport: TransportDirect(api!, racine.path),
          racineDocuments: racine.path,
        );

      final clair = File(env['E2EE_PNG']!).readAsBytesSync();
      final envoi = await suivi.lancer(
        fil: fil,
        convId: env['E2EE_CONV']!,
        pairId: env['E2EE_PAIR']!,
        fichier: MediaPickResult(bytes: clair, fileName: 'du-telephone.png', mimeType: 'image/png'),
        legende: env['E2EE_LEGENDE'] ?? '',
        // Sans base locale dans ce banc : ma copie se résume au message.
        rangerMaCopie: (id, d) async => Message(
          id: id,
          convId: env['E2EE_CONV']!,
          senderId: moi,
          content: '',
          type: 'IMAGE',
          status: 'SENT',
          replyToId: null,
          media: const [],
          createdAt: DateTime.now(),
          chiffre: true,
          mediaChiffre: d,
        ),
        apercu: (_) async => const Apercu(largeur: 40, hauteur: 30),
      );
      stdout.writeln('[mobile] RÉSERVÉ : envoi ${envoi.reservation.id}, '
          '${envoi.reservation.nbMorceaux} morceaux de ${envoi.reservation.tailleMorceau} octets');
      expect(envoi.reservation.nbMorceaux, greaterThan(1),
          reason: 'le banc doit forcer plusieurs morceaux');

      final pourcents = <int>{};
      envoi.progression.addListener(() => pourcents.add((envoi.progression.value * 100).floor()));
      final etat = await envoi.fin.timeout(const Duration(minutes: 3));

      stdout.writeln('[mobile] PUBLIÉ : message ${etat.messageId}, média ${envoi.reservation.mediaId}, '
          'pourcentages vus : ${(pourcents.toList()..sort()).join(", ")}');
      expect(etat.publie, isTrue, reason: 'publication : ${etat.publication}');
      expect(etat.messageId, envoi.messageId);
      expect(envoi.progression.value, 1);
      expect(pourcents.where((p) => p > 0 && p < 100), isNotEmpty,
          reason: 'des pourcentages intermédiaires doivent être passés');
      expect(Directory('${racine.path}/$dossierEnvoisMorceaux/${envoi.reservation.id}').existsSync(),
          isFalse,
          reason: 'le chiffré local est effacé une fois le fichier arrivé');
      racine.deleteSync(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: api == null ? 'banc manuel : variables E2EE_* absentes' : false,
  );
}
