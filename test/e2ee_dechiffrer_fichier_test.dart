import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le déchiffrement DE FICHIER À FICHIER (27/10/2026) rend exactement ce que
/// rend le déchiffrement en mémoire, et refuse ce qu'il refuse.
void main() {
  late Directory dossier;
  setUp(() => dossier = Directory.systemTemp.createTempSync('agb1-'));
  tearDown(() => dossier.deleteSync(recursive: true));

  final hasard = Random(7);
  Uint8List octets(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => hasard.nextInt(256)));

  for (final n in [0, 1, tailleBloc - 1, tailleBloc, tailleBloc * 3 + 17]) {
    test('aller-retour, $n octets', () {
      final clair = octets(n);
      final f = chiffrerFichier(clair);
      final source = File('${dossier.path}/c.bin')..writeAsBytesSync(f.chiffre);
      final cible = '${dossier.path}/d.bin';
      dechiffrerVersFichier(
          source: source.path, destination: cible, cle: f.cle, empreinte: f.empreinte, taille: n);
      expect(File(cible).readAsBytesSync(), clair);
    });
  }

  test('un fichier abîmé est refusé, et rien ne reste', () {
    final f = chiffrerFichier(octets(tailleBloc * 2));
    final abime = Uint8List.fromList(f.chiffre)..[10] ^= 1;
    final source = File('${dossier.path}/c.bin')..writeAsBytesSync(abime);
    final cible = '${dossier.path}/d.bin';
    expect(
      () => dechiffrerVersFichier(
          source: source.path, destination: cible, cle: f.cle, empreinte: f.empreinte, taille: tailleBloc * 2),
      throwsA(isA<FichierInvalide>()),
    );
    expect(File(cible).existsSync(), isFalse);
  });

  test('une clé fausse est refusée', () {
    final f = chiffrerFichier(octets(100));
    final autre = chiffrerFichier(octets(100));
    final source = File('${dossier.path}/c.bin')..writeAsBytesSync(f.chiffre);
    expect(
      () => dechiffrerVersFichier(
          source: source.path,
          destination: '${dossier.path}/d.bin',
          cle: autre.cle,
          empreinte: f.empreinte,
          taille: 100),
      throwsA(isA<FichierInvalide>()),
    );
  });
}
