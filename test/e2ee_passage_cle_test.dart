import 'dart:convert';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_groupe.dart' show deballerCle, emballerCle;
import 'package:alanya/services/e2ee/e2ee_sauvegarde.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' show Curve;

/// Le passage de la clé entre appareils et le bloc de contrôle (27/11/2026).
void main() {
  final maitresse = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
  final autre = Uint8List.fromList(List.generate(32, (i) => 255 - i));
  const compte = '11111111-2222-3333-4444-555555555555';

  group('bloc de contrôle', () {
    test('la bonne clé l’ouvre', () {
      final c = creerControle(maitresse, compte);
      expect(controleValide(maitresse, c, compte), isTrue);
    });

    test('une autre clé est refusée', () {
      final c = creerControle(maitresse, compte);
      expect(controleValide(autre, c, compte), isFalse);
    });

    test('lié au compte : servi à un autre compte, il est refusé', () {
      final c = creerControle(maitresse, compte);
      expect(controleValide(maitresse, c, 'un-autre-compte'), isFalse);
    });

    test('forme : 0x01 | nonce 12 | chiffré + étiquette, et assez court pour le serveur', () {
      final c = creerControle(maitresse, compte);
      final brut = base64.decode(c);
      expect(brut[0], 0x01);
      expect(brut.length, 1 + 12 + texteControle.length + 16);
      expect(c.length, lessThanOrEqualTo(128));
    });

    test('un bloc abîmé est refusé sans lever', () {
      expect(controleValide(maitresse, 'pas du base64 !', compte), isFalse);
      expect(controleValide(maitresse, base64.encode([1, 2, 3]), compte), isFalse);
    });
  });

  group('passage de la clé', () {
    test('la clé scellée pour la paire éphémère se rouvre à l’identique', () {
      final paire = Curve.generateKeyPair();
      final pub = Uint8List.fromList(paire.publicKey.serialize());
      final priv = Uint8List.fromList(paire.privateKey.serialize());
      final ctx = contexteDemande('demande-1', compte);
      final enveloppe = emballerCle(maitresse, pub, ctx);
      expect(deballerCle(enveloppe, priv, ctx), maitresse);
      // Assez court pour la route du serveur (200 caractères au plus).
      expect(enveloppe.length, lessThanOrEqualTo(200));
    });

    test('une autre demande ne rouvre pas l’enveloppe', () {
      final paire = Curve.generateKeyPair();
      final enveloppe = emballerCle(
        maitresse,
        Uint8List.fromList(paire.publicKey.serialize()),
        contexteDemande('demande-1', compte),
      );
      expect(
        () => deballerCle(
          enveloppe,
          Uint8List.fromList(paire.privateKey.serialize()),
          contexteDemande('demande-2', compte),
        ),
        throwsA(anything),
      );
    });

    test('la clé publique a la forme que le serveur exige (33 octets, 0x05)', () {
      final pub = base64.encode(Curve.generateKeyPair().publicKey.serialize());
      final brut = base64.decode(pub);
      expect(pub.length, 44);
      expect(brut.length, 33);
      expect(brut[0], 0x05);
    });
  });
}
