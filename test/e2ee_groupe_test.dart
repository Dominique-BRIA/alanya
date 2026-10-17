// LE CHIFFREMENT DE GROUPE, WEB ↔ MOBILE (lot 1, cours chapitre 32).
//
// Le vecteur `test/donnees/vecteur_groupe_web.json` est produit par
// `STAGE-WEB/scripts/e2ee-groupe-vecteur.mjs --ecrire`. Le téléphone doit le
// lire, refuser sa version falsifiée, et produire le MÊME chiffré avec le même
// nonce. L'autre sens (le web lit le téléphone) est vérifié par ce même banc
// web, sur `vecteur_groupe_mobile.json`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_groupe.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart' show ecrireCharge;
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

ContexteGroupe _contexte(Map<String, dynamic> c) => ContexteGroupe(
      convId: c['convId'] as String,
      messageId: c['messageId'] as String,
      version: c['version'] as int,
      expediteurId: c['expediteurId'] as String,
      deviceId: c['deviceId'] as int,
    );

ContexteGroupe _autre(ContexteGroupe c,
        {String? convId, String? messageId, int? version, String? expediteurId}) =>
    ContexteGroupe(
      convId: convId ?? c.convId,
      messageId: messageId ?? c.messageId,
      version: version ?? c.version,
      expediteurId: expediteurId ?? c.expediteurId,
      deviceId: c.deviceId,
    );

void main() {
  group('le vecteur du WEB', () {
    final v = jsonDecode(File('test/donnees/vecteur_groupe_web.json').readAsStringSync())
        as Map<String, dynamic>;
    final cle = base64Decode(v['cle'] as String);
    final cleWeb = base64Decode(v['clePublique'] as String);
    final ctx = _contexte(v['contexte'] as Map<String, dynamic>);

    test('le téléphone lit le message du web', () {
      expect(dechiffrerMessageGroupe(v['corps'] as String, cle, ctx, cleWeb), v['clair']);
    });

    test('sa version falsifiée est refusée', () {
      final brut = base64Decode(v['corps'] as String);
      brut[brut.length - 1] ^= 1;
      expect(() => dechiffrerMessageGroupe(base64Encode(brut), cle, ctx, cleWeb),
          throwsA(isA<GroupeInvalide>()));
    });

    test('même nonce : le téléphone produit le MÊME chiffré que le web', () {
      final refait = base64Decode(chiffrerMessageGroupe(
        v['clair'] as String,
        cle,
        ctx,
        Curve.generateKeyPair().privateKey.serialize(),
        nonceImpose: base64Decode(v['nonce'] as String),
      ));
      final web = base64Decode(v['corps'] as String);
      expect(base64Encode(refait.sublist(0, refait.length - 64)),
          base64Encode(web.sublist(0, web.length - 64)));
    });

    test('charge trousseau : identique octet pour octet', () {
      final t = v['trousseau'] as Map<String, dynamic>;
      final trousseau = Trousseau(
        convId: t['convId'] as String,
        motif: t['motif'] as String,
        versions: [
          for (final x in t['versions'] as List)
            VersionCle(
              n: x['n'] as int,
              cle: base64Decode(x['cle'] as String),
              creeLe: x['creeLe'] as int,
            ),
        ],
      );
      expect(ecrireChargeTrousseau(trousseau), v['chargeTrousseau']);
      final relu = lireChargeTrousseau(v['chargeTrousseau'] as String, t['convId'] as String);
      expect(relu.versions.map((x) => x.n), [1, 2]);
    });
  });

  group('les refus, sur le téléphone', () {
    final paire = Curve.generateKeyPair();
    final prive = paire.privateKey.serialize();
    final public = paire.publicKey.serialize();
    final cle = genererCleGroupe();
    const ctx = ContexteGroupe(
      convId: 'aaaaaaaa-0000-4000-8000-000000000001',
      messageId: 'bbbbbbbb-0000-4000-8000-000000000002',
      version: 1,
      expediteurId: 'cccccccc-0000-4000-8000-000000000003',
      deviceId: 1,
    );
    final clair = ecrireCharge(ctx.messageId, 'Salut');
    final corps = chiffrerMessageGroupe(clair, cle, ctx, prive);

    test('aller-retour', () {
      expect(dechiffrerMessageGroupe(corps, cle, ctx, public), clair);
    });

    test('signé par un autre appareil : refusé', () {
      expect(
          () => dechiffrerMessageGroupe(
              corps, cle, ctx, Curve.generateKeyPair().publicKey.serialize()),
          throwsA(isA<GroupeInvalide>()));
    });

    test('déplacé : autre message, autre groupe, autre expéditeur, autre version', () {
      for (final c in [
        _autre(ctx, messageId: 'dddddddd-0000-4000-8000-000000000004'),
        _autre(ctx, convId: 'eeeeeeee-0000-4000-8000-000000000005'),
        _autre(ctx, expediteurId: 'ffffffff-0000-4000-8000-000000000006'),
        _autre(ctx, version: 2),
      ]) {
        expect(() => dechiffrerMessageGroupe(corps, cle, c, public),
            throwsA(isA<GroupeInvalide>()));
      }
    });

    test('mauvaise clé de groupe : refusée', () {
      expect(() => dechiffrerMessageGroupe(corps, genererCleGroupe(), ctx, public),
          throwsA(isA<GroupeInvalide>()));
    });

    test('trousseau d’un autre groupe : refusé ; clé remplacée : refusée', () {
      final charge = ecrireChargeTrousseau(Trousseau(
        convId: ctx.convId,
        motif: 'AJOUT',
        versions: [VersionCle(n: 1, cle: cle, creeLe: 1)],
      ));
      expect(() => lireChargeTrousseau(charge, 'autre'), throwsA(isA<GroupeInvalide>()));
      final connu = lireChargeTrousseau(charge, ctx.convId).versions;
      expect(
          () => fusionnerTrousseau(connu, [VersionCle(n: 1, cle: Uint8List(32), creeLe: 2)]),
          throwsA(isA<GroupeInvalide>()));
      expect(
          fusionnerTrousseau(connu, [VersionCle(n: 2, cle: Uint8List(32), creeLe: 2)]).length,
          2);
    });
  });
}
