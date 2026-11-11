import 'dart:convert';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_compte.dart';
import 'package:alanya/services/e2ee/e2ee_groupe.dart' as g;
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' show Curve;

/// CHIFFREMENT DES GROUPES V2 — lot 3 (11/11/2026).
///
/// Les VECTEURS (clés, éphémère et nonce fixés) sont le contrat avec le web
/// (lot 4, `STAGE-WEB/src/services/e2ee-groupe.ts`) : le même calcul doit y
/// produire les mêmes octets. Ne pas les modifier sans modifier le web.
Uint8List _octets(int depart, int n) => Uint8List.fromList(List.generate(n, (i) => (depart + i) & 0xff));

void main() {
  const conv = '11111111-1111-4111-8111-111111111111';
  const msg = '22222222-2222-4222-8222-222222222222';
  const ana = '33333333-3333-4333-8333-333333333333';
  final cleGroupe = _octets(1, 32);
  final nonce = _octets(100, 12);
  final contexte = g.ContexteGroupe(
      convId: conv, messageId: msg, version: 3, expediteurId: ana, deviceId: 7);

  group('message de groupe, format 2', () {
    test('aller-retour', () {
      final corps = g.chiffrerMessageGroupeV2('Bonjour le groupe', cleGroupe, contexte);
      expect(g.formatDuCorps(corps), g.formatGroupeV2);
      expect(g.dechiffrerMessageGroupeV2(corps, cleGroupe, contexte), 'Bonjour le groupe');
    });

    test("l'appareil ne fait pas partie des données associées", () {
      final corps = g.chiffrerMessageGroupeV2('x', cleGroupe, contexte);
      final autreAppareil = g.ContexteGroupe(
          convId: conv, messageId: msg, version: 3, expediteurId: ana, deviceId: 99);
      expect(g.dechiffrerMessageGroupeV2(corps, cleGroupe, autreAppareil), 'x');
    });

    test('un autre expéditeur, message ou version : refusé', () {
      final corps = g.chiffrerMessageGroupeV2('x', cleGroupe, contexte);
      for (final faux in [
        g.ContexteGroupe(convId: conv, messageId: msg, version: 3, expediteurId: 'bob', deviceId: 7),
        g.ContexteGroupe(convId: conv, messageId: 'autre', version: 3, expediteurId: ana, deviceId: 7),
        g.ContexteGroupe(convId: conv, messageId: msg, version: 4, expediteurId: ana, deviceId: 7),
      ]) {
        expect(() => g.dechiffrerMessageGroupeV2(corps, cleGroupe, faux),
            throwsA(isA<g.GroupeInvalide>()));
      }
    });

    test('vecteur figé (contrat avec le web)', () {
      final corps =
          g.chiffrerMessageGroupeV2('Bonjour le groupe', cleGroupe, contexte, nonceImpose: nonce);
      expect(corps, vecteurMessageV2);
    });
  });

  group('format 1 sans signature', () {
    test("se lit quand l'identité de l'auteur est inconnue", () {
      final identite = Curve.generateKeyPair();
      final corps = g.chiffrerMessageGroupe(
          'ancien message', cleGroupe, contexte, Uint8List.fromList(identite.privateKey.serialize()));
      expect(g.dechiffrerMessageGroupeSansSignature(corps, cleGroupe, contexte), 'ancien message');
    });

    test("mais l'appareil reste dans ses données associées", () {
      final identite = Curve.generateKeyPair();
      final corps = g.chiffrerMessageGroupe(
          'x', cleGroupe, contexte, Uint8List.fromList(identite.privateKey.serialize()));
      final autre = g.ContexteGroupe(
          convId: conv, messageId: msg, version: 3, expediteurId: ana, deviceId: 8);
      expect(() => g.dechiffrerMessageGroupeSansSignature(corps, cleGroupe, autre),
          throwsA(isA<g.GroupeInvalide>()));
    });
  });

  group('emballage pour un compte', () {
    final compte = Curve.generateKeyPairFromPrivate(_octets(50, 32));
    final pub = Uint8List.fromList(compte.publicKey.serialize());
    final priv = Uint8List.fromList(compte.privateKey.serialize());
    const ctx = g.ContexteEmballage(convId: conv, destinataireId: ana, version: 3, versionCompte: 1);

    test('aller-retour', () {
      final corps = g.emballerCle(cleGroupe, pub, ctx);
      expect(g.deballerCle(corps, priv, ctx), cleGroupe);
    });

    test('un autre compte, groupe ou version : refusé', () {
      final corps = g.emballerCle(cleGroupe, pub, ctx);
      final autre = Curve.generateKeyPair();
      expect(() => g.deballerCle(corps, Uint8List.fromList(autre.privateKey.serialize()), ctx),
          throwsA(isA<g.GroupeInvalide>()));
      for (final faux in const [
        g.ContexteEmballage(convId: 'autre', destinataireId: ana, version: 3, versionCompte: 1),
        g.ContexteEmballage(convId: conv, destinataireId: 'bob', version: 3, versionCompte: 1),
        g.ContexteEmballage(convId: conv, destinataireId: ana, version: 2, versionCompte: 1),
        g.ContexteEmballage(convId: conv, destinataireId: ana, version: 3, versionCompte: 2),
      ]) {
        expect(() => g.deballerCle(corps, priv, faux), throwsA(isA<g.GroupeInvalide>()));
      }
    });

    test('vecteur figé (contrat avec le web)', () {
      final eph = Curve.generateKeyPairFromPrivate(_octets(150, 32));
      final corps = g.emballerCle(cleGroupe, pub, ctx,
          ephemere: (
            pub: Uint8List.fromList(eph.publicKey.serialize()),
            priv: Uint8List.fromList(eph.privateKey.serialize()),
          ),
          nonceImpose: nonce);
      expect(base64.encode(pub), vecteurComptePub);
      expect(corps, vecteurEmballage);
    });
  });

  test('clé de compte : aller-retour JSON et données associées', () {
    final k = Curve.generateKeyPair();
    final cle = CleCompte(
      version: 2,
      pub: Uint8List.fromList(k.publicKey.serialize()),
      priv: Uint8List.fromList(k.privateKey.serialize()),
    );
    final relue = CleCompte.depuisJson(cle.versJson())!;
    expect(relue.version, 2);
    expect(relue.pub, cle.pub);
    expect(relue.priv, cle.priv);
    expect(utf8.decode(aadCleCompte(ana, 2)), 'alanya-compte-v1\n$ana\n2');
  });
}

// Les vecteurs : calculés une fois, puis figés.
const vecteurMessageV2 = 'AmRlZmdoaWprbG1ubyIwHSb+985ZlDKP/2pDjUyRc+YZz/lY1BCHK5Asa01r9g==';
const vecteurComptePub = 'BeBbGuMiAkg4CV/979hlRo3bd7FLLdJ1F16gq0KU+m16';
const vecteurEmballage =
    'AQUIJkrmkLQR2OPt5A+HGSWF6hFKCCdEp3YQWqwF6rEFLmRlZmdoaWprbG1ubxDT344+T9b0Bx8lD2B9BxgRb1EmaM9aJ9p9Jd1mjwWmO9bZdt1oih8EAOOO8XsW2Q==';
