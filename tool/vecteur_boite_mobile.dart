// Écrit `test/donnees/vecteur_boite_mobile.json` : la boîte permanente que le
// WEB doit savoir ouvrir (cours, chapitre 39). Jumeau de l'option `--ecrire` de
// `STAGE-WEB/scripts/e2ee-boite-vecteur.mjs`.
//
// Lancer depuis `alanya` : dart run tool/vecteur_boite_mobile.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_groupe.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

({Uint8List pub, Uint8List priv}) paire() {
  final k = Curve.generateKeyPair();
  return (pub: Uint8List.fromList(k.publicKey.serialize()), priv: Uint8List.fromList(k.privateKey.serialize()));
}

void main() {
  final destinataire = paire();
  final expediteur = paire();
  final ephemere = paire();
  final nonce = Uint8List.fromList(List<int>.generate(12, (i) => 120 + i));
  const contexte = ContexteBoite(
    convId: '11111111-aaaa-4bbb-8ccc-dddddddddddd',
    destinataireId: '55555555-6666-4777-8888-999999999999',
    destinataireDevice: 12,
    expediteurId: '33333333-2222-4333-8444-555555555555',
    expediteurDevice: 4,
  );
  const clair = '\u0000G1{"v":1,"type":"trousseau","convId":"11111111-aaaa-4bbb-8ccc-dddddddddddd",'
      '"motif":"EXCLUSION","versions":[]} — é 🎉';
  final corps = scellerBoite(clair, destinataire.pub, contexte, expediteur.priv,
      ephemere: ephemere, nonceImpose: nonce);
  final vecteur = {
    'source': 'mobile',
    'contexte': {
      'convId': contexte.convId,
      'destinataireId': contexte.destinataireId,
      'destinataireDevice': contexte.destinataireDevice,
      'expediteurId': contexte.expediteurId,
      'expediteurDevice': contexte.expediteurDevice,
    },
    'clair': clair,
    'corps': corps,
    'destinataire': {'pub': base64Encode(destinataire.pub), 'priv': base64Encode(destinataire.priv)},
    'expediteur': {'pub': base64Encode(expediteur.pub), 'priv': base64Encode(expediteur.priv)},
    'ephemere': {'pub': base64Encode(ephemere.pub), 'priv': base64Encode(ephemere.priv)},
    'nonce': base64Encode(nonce),
  };
  File('test/donnees/vecteur_boite_mobile.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(vecteur)}\n');
  stdout.writeln('→ test/donnees/vecteur_boite_mobile.json');
}
