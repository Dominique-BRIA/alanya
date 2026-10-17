// LA BOÎTE PERMANENTE, CÔTÉ MOBILE — cours, chapitre 39.
//
// ① aller-retour ; ② refus (autre appareil, autre signataire, boîte déplacée,
// chiffré altéré, signature falsifiée) ; ③ le vecteur du WEB s'ouvre ici, et
// le même scellé se refait à l'octet près (même éphémère, même nonce ; la
// signature, aléatoire, est seulement vérifiée).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_groupe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

({Uint8List pub, Uint8List priv}) paire() {
  final k = Curve.generateKeyPair();
  return (pub: Uint8List.fromList(k.publicKey.serialize()), priv: Uint8List.fromList(k.privateKey.serialize()));
}

void main() {
  const contexte = ContexteBoite(
    convId: '11111111-aaaa-4bbb-8ccc-dddddddddddd',
    destinataireId: '44444444-1111-4222-8333-444444444444',
    destinataireDevice: 7,
    expediteurId: '33333333-2222-4333-8444-555555555555',
    expediteurDevice: 4,
  );
  const clair = '\u0000G1{"v":1,"type":"trousseau","versions":[]} — ç';
  final destinataire = paire();
  final expediteur = paire();

  test('① aller-retour', () {
    final corps = scellerBoite(clair, destinataire.pub, contexte, expediteur.priv);
    expect(ouvrirBoite(corps, destinataire.priv, contexte, expediteur.pub), clair);
    expect(scellerBoite(clair, destinataire.pub, contexte, expediteur.priv), isNot(corps));
  });

  test('② les refus', () {
    final corps = scellerBoite(clair, destinataire.pub, contexte, expediteur.priv);
    final autre = paire();
    void refuse(String nom, void Function() f) =>
        expect(f, throwsA(isA<GroupeInvalide>()), reason: nom);
    refuse('autre appareil', () => ouvrirBoite(corps, autre.priv, contexte, expediteur.pub));
    refuse('autre signataire', () => ouvrirBoite(corps, destinataire.priv, contexte, autre.pub));
    refuse(
        'autre groupe',
        () => ouvrirBoite(
            corps,
            destinataire.priv,
            const ContexteBoite(
                convId: 'eeeeeeee-0000-4000-8000-000000000000',
                destinataireId: '44444444-1111-4222-8333-444444444444',
                destinataireDevice: 7,
                expediteurId: '33333333-2222-4333-8444-555555555555',
                expediteurDevice: 4),
            expediteur.pub));
    final altere = base64.decode(corps);
    altere[60] ^= 0xff;
    refuse('chiffré altéré', () => ouvrirBoite(base64.encode(altere), destinataire.priv, contexte, expediteur.pub));
    final falsifie = base64.decode(corps);
    falsifie[falsifie.length - 1] ^= 0x01;
    refuse('signature falsifiée',
        () => ouvrirBoite(base64.encode(falsifie), destinataire.priv, contexte, expediteur.pub));
  });

  test('③ le vecteur du web', () {
    final v = jsonDecode(File('test/donnees/vecteur_boite_web.json').readAsStringSync()) as Map<String, dynamic>;
    Uint8List b(String s) => Uint8List.fromList(base64.decode(s));
    final c = v['contexte'] as Map<String, dynamic>;
    final ctx = ContexteBoite(
      convId: c['convId'] as String,
      destinataireId: c['destinataireId'] as String,
      destinataireDevice: c['destinataireDevice'] as int,
      expediteurId: c['expediteurId'] as String,
      expediteurDevice: c['expediteurDevice'] as int,
    );
    final dest = v['destinataire'] as Map<String, dynamic>;
    final exp = v['expediteur'] as Map<String, dynamic>;
    final eph = v['ephemere'] as Map<String, dynamic>;
    expect(ouvrirBoite(v['corps'] as String, b(dest['priv'] as String), ctx, b(exp['pub'] as String)), v['clair'],
        reason: 'le mobile ouvre la boîte du web');
    final refait = scellerBoite(v['clair'] as String, b(dest['pub'] as String), ctx, b(exp['priv'] as String),
        ephemere: (pub: b(eph['pub'] as String), priv: b(eph['priv'] as String)), nonceImpose: b(v['nonce'] as String));
    String sansSignature(String s) {
      final o = base64.decode(s);
      return base64.encode(o.sublist(0, o.length - 64));
    }

    expect(sansSignature(refait), sansSignature(v['corps'] as String), reason: 'même scellé que le web');
    expect(ouvrirBoite(refait, b(dest['priv'] as String), ctx, b(exp['pub'] as String)), v['clair']);
  });
}
