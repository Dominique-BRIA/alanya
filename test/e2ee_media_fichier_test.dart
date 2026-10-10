import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:alanya/services/e2ee/e2ee_media_fichier.dart';

/// CHIFFRER DE FICHIER À FICHIER DOIT DONNER LES MÊMES OCTETS (cours, ch. 43).
///
/// Le destinataire — web ou mobile, ancien ou récent — déchiffre avec
/// [dechiffrerFichier], qui ne connaît que le format AGB1. Le chiffrement en
/// flux n'a donc AUCUNE latitude : à clé égale, il doit reproduire
/// [chiffrerFichier] octet pour octet, empreinte comprise.
///
/// Les tailles visées sont les bords du découpage en blocs de 64 Kio : vide,
/// un octet, juste avant / pile sur / juste après une frontière, plusieurs
/// blocs avec un reste.
///
/// Lancer avec : flutter test test/e2ee_media_fichier_test.dart
void main() {
  late Directory dossier;
  final cle = Uint8List.fromList(List<int>.generate(32, (i) => i * 7 + 3));
  final hasard = Random(42);
  Uint8List octetsDe(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => hasard.nextInt(256)));

  setUp(() => dossier = Directory.systemTemp.createTempSync('agb1_'));
  tearDown(() => dossier.deleteSync(recursive: true));

  const tailles = {
    'vide': 0,
    'un octet': 1,
    'un bloc moins un': tailleBloc - 1,
    'un bloc pile': tailleBloc,
    'un bloc plus un': tailleBloc + 1,
    'trois blocs et un reste': 3 * tailleBloc + 17,
    '1,2 Mo': 1200 * 1024 + 5,
  };

  for (final MapEntry(key: nom, value: n) in tailles.entries) {
    test('$nom ($n octets) : mêmes octets que chiffrerFichier', () {
      final clair = octetsDe(n);
      final source = File('${dossier.path}/clair.bin')..writeAsBytesSync(clair);
      final attendu = chiffrerFichier(clair, cleImposee: cle);

      final depuisFichier = chiffrerVersFichier(
          destination: '${dossier.path}/a.bin', source: source.path, cleImposee: cle);
      final depuisOctets = chiffrerVersFichier(
          destination: '${dossier.path}/b.bin', octets: clair, cleImposee: cle);

      for (final r in [depuisFichier, depuisOctets]) {
        final ecrit = File(r.chemin).readAsBytesSync();
        expect(ecrit, attendu.chiffre, reason: 'octets du chiffré');
        expect(r.empreinteBase64, attendu.empreinte, reason: 'empreinte');
        expect(r.cle, attendu.cle);
        expect(r.taille, attendu.chiffre.length);
        expect(r.tailleClair, n);
        // Et le destinataire le relit.
        expect(
          dechiffrerFichier(ecrit, cle: r.cle, empreinte: r.empreinteBase64, taille: n),
          clair,
        );
      }
    });
  }

  test("l'empreinte hexadécimale (celle du serveur) est la même que la base64", () {
    final r = chiffrerVersFichier(
        destination: '${dossier.path}/c.bin', octets: octetsDe(1000), cleImposee: cle);
    expect(r.empreinteHex, matches(RegExp(r'^[0-9a-f]{64}$')));
    final depuisHex = Uint8List.fromList(List<int>.generate(
        32, (i) => int.parse(r.empreinteHex.substring(2 * i, 2 * i + 2), radix: 16)));
    expect(depuisHex, empreinteDe(File(r.chemin).readAsBytesSync()));
  });

  test('sans clé imposée : une clé NEUVE à chaque fichier', () {
    final clair = octetsDe(500);
    final a = chiffrerVersFichier(destination: '${dossier.path}/d.bin', octets: clair);
    final b = chiffrerVersFichier(destination: '${dossier.path}/e.bin', octets: clair);
    expect(a.cle, isNot(b.cle));
    expect(dechiffrerFichier(File(a.chemin).readAsBytesSync(),
        cle: a.cle, empreinte: a.empreinteBase64, taille: 500), clair);
  });

  test('une source introuvable ne laisse AUCUN chiffré à moitié écrit', () {
    final destination = '${dossier.path}/f.bin';
    expect(
      () => chiffrerVersFichier(destination: destination, source: '${dossier.path}/absent.bin'),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(destination).existsSync(), isFalse);
  });

  test("dans un isolat (le chemin de l'application)", () async {
    final clair = octetsDe(3 * tailleBloc + 1);
    final source = File('${dossier.path}/g-clair.bin')..writeAsBytesSync(clair);
    final r = await chiffrerVersFichierHorsDuFil(
        destination: '${dossier.path}/g.bin', source: source.path);
    expect(dechiffrerFichier(File(r.chemin).readAsBytesSync(),
        cle: r.cle, empreinte: r.empreinteBase64, taille: clair.length), clair);
  });
}
