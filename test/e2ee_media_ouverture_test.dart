// LE TÉLÉCHARGEMENT D'UN MÉDIA CHIFFRÉ FINIT TOUJOURS — en succès ou en erreur.
//
// 🐛 Le chargement d'un média chiffré tournait sans fin sur le téléphone
// (user, 03/10/2026) : un `http.get` sans délai, face à une connexion muette,
// ne se terminait jamais. Un vrai serveur local joue ici les trois cas.

import 'dart:async';
import 'dart:io';

import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:alanya/services/e2ee/e2ee_media_ouverture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dossier;
  late HttpServer serveur;
  late String base;
  // Ce que le serveur de test fait de chaque requête.
  late Future<void> Function(HttpRequest) repondre;
  final recues = <HttpRequest>[];

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('e2ee-ouverture-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => dossier.path,
    );
    recues.clear();
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${serveur.port}';
    serveur.listen((r) {
      recues.add(r);
      repondre(r);
    });
    OuvertureMediaChiffre.delaiInactivite = const Duration(milliseconds: 300);
  });

  tearDown(() async {
    await serveur.close(force: true);
    await dossier.delete(recursive: true);
  });

  DescripteurMedia descripteur(String id, FichierChiffre f, int taille) =>
      DescripteurMedia(
        id: id,
        cle: f.cle,
        empreinte: f.empreinte,
        taille: taille,
        mime: 'image/png',
        nom: 'photo.png',
      );

  test('une connexion muette finit en ERREUR, et un nouvel essai repart',
      () async {
    // Le banc de Flutter remplace le client HTTP par un faux à chaque test.
    HttpOverrides.global = null;
    final clair = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final f = chiffrerFichier(clair);
    // Le serveur accepte et ne répond jamais.
    repondre = (_) async {};

    final debut = DateTime.now();
    await expectLater(
      OuvertureMediaChiffre.ouvrir(descripteur('muet', f, clair.length),
          baseUrl: base, token: 'jeton'),
      throwsA(isA<TimeoutException>()),
    );
    // Trois essais de 300 ms et deux pauses : bien loin de « jamais ».
    expect(DateTime.now().difference(debut), lessThan(const Duration(seconds: 5)));
    expect(recues.length, 3, reason: 'deux nouvelles tentatives');

    // Le Future mort n'est pas gardé : le serveur répond enfin, ça passe.
    repondre = (r) async {
      r.response.add(f.chiffre);
      await r.response.close();
    };
    final fichier = await OuvertureMediaChiffre.ouvrir(
        descripteur('muet', f, clair.length),
        baseUrl: base,
        token: 'jeton');
    expect(await fichier.readAsBytes(), clair);
  });

  test('le jeton part en EN-TÊTE, comme pour les autres médias', () async {
    // Le banc de Flutter remplace le client HTTP par un faux à chaque test.
    HttpOverrides.global = null;
    final clair = Uint8List.fromList(List.generate(500, (i) => i % 7));
    final f = chiffrerFichier(clair);
    repondre = (r) async {
      r.response.add(f.chiffre);
      await r.response.close();
    };
    await OuvertureMediaChiffre.ouvrir(descripteur('entete', f, clair.length),
        baseUrl: base, token: 'abc.def.ghi');
    expect(recues.single.headers.value('authorization'), 'Bearer abc.def.ghi');
    expect(recues.single.uri.queryParameters.containsKey('token'), isFalse);
  });

  test('un refus du serveur finit en MediaIndisponible, sans réessayer',
      () async {
    // Le banc de Flutter remplace le client HTTP par un faux à chaque test.
    HttpOverrides.global = null;
    final f = chiffrerFichier(Uint8List(10));
    repondre = (r) async {
      r.response.statusCode = 401;
      await r.response.close();
    };
    await expectLater(
      OuvertureMediaChiffre.ouvrir(descripteur('refus', f, 10),
          baseUrl: base, token: 'perime'),
      throwsA(isA<MediaIndisponible>()),
    );
    expect(recues.length, 1);
  });
}
