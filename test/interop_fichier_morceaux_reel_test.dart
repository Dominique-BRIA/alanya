// UN FICHIER EN CLAIR ENVOYÉ EN MORCEAUX, L'APPLICATION « TUÉE » AU MILIEU,
// PUIS REPRIS PAR SA RÉSERVATION — contre le vrai serveur (cours, ch. 45).
//
// Le vrai `SuiviEnvoisMorceaux` : `lancerFichier` (chemin en clair, lot 4),
// puis `suivre` après un « redémarrage ». Un premier transport ne pousse
// qu'UN morceau et disparaît — comme une application tuée avant qu'Android ait
// tout envoyé ; un second reprend. Le serveur doit rendre le fichier ENTIER,
// octet pour octet, sous son vrai type.
//
// ⚠️ IGNORÉ SANS E2EE_API (serveur local démarré, compte de banc
// alice.media@e2ee.test lié à l'appareil banc-media-mobile-alice).
//   E2EE_API=http://localhost:3000 flutter test test/interop_fichier_morceaux_reel_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:alanya/core/api_client.dart';
import 'package:alanya/core/authed_api.dart';
import 'package:alanya/core/token_storage.dart';
import 'package:alanya/features/chat/envoi_morceaux/decoupage_morceaux.dart';
import 'package:alanya/features/chat/envoi_morceaux/envoi_morceaux_api.dart';
import 'package:alanya/features/chat/envoi_morceaux/envoi_morceaux_chiffre.dart';
import 'package:alanya/features/chat/envoi_morceaux/transport_morceaux.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Jetons extends TokenStorage {
  _Jetons(this._jeton);
  final String _jeton;
  @override
  Future<String?> get accessToken async => _jeton;
  @override
  Future<String?> get refreshToken async => null;
}

/// Un transport qui ne pousse que le PREMIER morceau qu'on lui confie, puis
/// plus rien : l'application est morte avant qu'Android ait fini.
class _TransportQuiMeurt implements TransportMorceaux {
  _TransportQuiMeurt(this._vrai);
  final TransportDirect _vrai;
  @override
  Stream<EvenementMorceau> get evenements => _vrai.evenements;
  @override
  Future<void> confier(ReservationEnvoi r, String chemin, List<Morceau> morceaux,
          {required String titre}) =>
      _vrai.confier(r, chemin, morceaux.take(1).toList(), titre: titre);
  @override
  Future<Set<int>> enVol(String envoiId) async => {};
  @override
  Future<void> annuler(String envoiId) async {}
}

void main() {
  final api = Platform.environment['E2EE_API'];

  test(
    'fichier en clair : un morceau, la mort, la reprise, le fichier entier',
    () async {
      HttpOverrides.global = null;
      final connexion = await http.post(Uri.parse('$api/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'identifier': 'alice.media@e2ee.test',
            'password': 'MotDePasseDeTest!2026',
            'deviceId': 'banc-media-mobile-alice',
            'typeDevice': 1,
          }));
      expect(connexion.statusCode, 200, reason: connexion.body);
      final jeton = (jsonDecode(connexion.body) as Map)['accessToken'] as String;
      final apiEnvois =
          EnvoiMorceauxApi(AuthedApi(ApiClient(baseUrl: api), _Jetons(jeton)), base: api);

      // Le fichier, là où la file d'envoi le range : sous les documents.
      final racine = Directory.systemTemp.createTempSync('fichier_morceaux_');
      const chemin = 'envois_en_attente/banc/0_video.mp4';
      // Un hasard tiré UNE fois : un octet répété ne verrait pas un morceau
      // écrit au mauvais endroit.
      final hasard = Random(7);
      final contenu = Uint8List.fromList(
          List<int>.generate(2 * 1024 * 1024 + 4321, (_) => hasard.nextInt(256)));
      File('${racine.path}/$chemin')
        ..createSync(recursive: true)
        ..writeAsBytesSync(contenu);

      // 1. L'application lance l'envoi… et meurt après un morceau.
      final moteur = SuiviEnvoisMorceaux.instance
        ..brancher(
          api: apiEnvois,
          transport: _TransportQuiMeurt(TransportDirect(api!, racine.path)),
          racineDocuments: racine.path,
        );
      final premier = await moteur.lancerFichier(
          cheminRelatif: chemin, nom: 'video.mp4', mime: 'video/mp4');
      final r = premier.reservation;
      stdout.writeln('[mobile] envoi ${r.id} : ${r.nbMorceaux} morceaux');
      expect(r.nbMorceaux, 3);
      await Future<void>.delayed(const Duration(seconds: 3));
      final avant = await apiEnvois.etat(r.id, r.jeton);
      expect(avant.termine, isFalse);
      expect(avant.manquants, [1, 2], reason: 'seul le morceau 0 est parti');
      moteur.debrancher();

      // 2. « Redémarrage » : la file d'envoi retrouve sa réservation.
      moteur.brancher(
        api: apiEnvois,
        transport: TransportDirect(api, racine.path),
        racineDocuments: racine.path,
      );
      final repris = moteur.suivre(r, chemin);
      final etat = await repris.fin.timeout(const Duration(minutes: 2));
      expect(etat.termine, isTrue);
      expect(repris.progression.value, 1);
      expect(Directory('${racine.path}/$dossierEnvoisMorceaux/${r.id}').existsSync(), isFalse,
          reason: 'le registre est effacé une fois le fichier arrivé');

      // 3. Le serveur rend le fichier ENTIER, sous son vrai type.
      final media = await http.get(Uri.parse('$api/api/media/${r.mediaId}'),
          headers: {'Authorization': 'Bearer $jeton'});
      expect(media.statusCode, 200);
      expect(media.headers['content-type'], startsWith('video/mp4'));
      expect(media.bodyBytes, contenu, reason: 'octet pour octet');
      stdout.writeln('[mobile] média ${r.mediaId} : ${media.bodyBytes.length} octets, identiques');

      moteur.debrancher();
      racine.deleteSync(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: api == null ? 'banc manuel : E2EE_API absente' : false,
  );
}
