// Écrit `test/donnees/vecteur_groupe_mobile.json` : le message de groupe que le
// WEB doit savoir lire (cours, chapitre 32). Jumeau de l'option `--ecrire` de
// `STAGE-WEB/scripts/e2ee-groupe-vecteur.mjs`.
//
// Lancer depuis `alanya` : dart run tool/vecteur_groupe_mobile.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_groupe.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart' show ecrireCharge;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

void main() {
  final paire = Curve.generateKeyPair();
  final clePrivee = paire.privateKey.serialize();
  final clePublique = paire.publicKey.serialize();

  final cle = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
  final nonce = Uint8List.fromList(List<int>.generate(12, (i) => 50 + i));
  const contexte = ContexteGroupe(
    convId: '11111111-aaaa-4bbb-8ccc-dddddddddddd',
    messageId: '22222222-eeee-4fff-8000-111111111111',
    version: 2,
    expediteurId: '33333333-2222-4333-8444-555555555555',
    deviceId: 4,
  );
  final clair = ecrireCharge(contexte.messageId, 'Message du téléphone — ç 🎉');
  final corps = chiffrerMessageGroupe(clair, cle, contexte, clePrivee, nonceImpose: nonce);

  final trousseau = Trousseau(convId: contexte.convId, motif: 'EXCLUSION', versions: [
    VersionCle(n: 1, cle: Uint8List.fromList(List<int>.generate(32, (i) => i * 7 % 256)), creeLe: 1758000000000),
    VersionCle(n: 2, cle: Uint8List.fromList(List<int>.generate(32, (i) => (i * 11 + 3) % 256)), creeLe: 1760500000000),
  ]);

  final vecteur = {
    'source': 'mobile',
    'cle': base64Encode(cle),
    'nonce': base64Encode(nonce),
    'contexte': {
      'convId': contexte.convId,
      'messageId': contexte.messageId,
      'version': contexte.version,
      'expediteurId': contexte.expediteurId,
      'deviceId': contexte.deviceId,
    },
    'clair': clair,
    'corps': corps,
    'clePublique': base64Encode(clePublique),
    'chargeTrousseau': ecrireChargeTrousseau(trousseau),
    'trousseau': {
      'convId': trousseau.convId,
      'motif': trousseau.motif,
      'versions': [
        for (final v in trousseau.versions) {'n': v.n, 'cle': base64Encode(v.cle), 'creeLe': v.creeLe},
      ],
    },
  };
  File('test/donnees/vecteur_groupe_mobile.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(vecteur)}\n');
  stdout.writeln('→ test/donnees/vecteur_groupe_mobile.json');
}
