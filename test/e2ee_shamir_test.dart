import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_contacts_recuperation.dart';
import 'package:alanya/services/e2ee/e2ee_groupe.dart' show deballerCle, emballerCle;
import 'package:alanya/services/e2ee/e2ee_shamir.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' show Curve;
import 'package:flutter_test/flutter_test.dart';

String _hex(Uint8List o) => o.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Le partage de Shamir des contacts de récupération (27/11/2026).
void main() {
  final secret = Uint8List.fromList(List.generate(32, (i) => (i * 37 + 11) & 0xff));
  Uint8List coefficients(int l) => Uint8List.fromList(List.generate(l, (i) => (i * 91 + 5) & 0xff));

  test('le produit d’AES (0x57·0x83 = 0xc1) et les 255 inverses', () {
    expect(multiplierGf(0x57, 0x83), 0xc1);
    for (var a = 1; a < 256; a++) {
      expect(multiplierGf(a, inverserGf(a)), 1, reason: 'inverse de $a');
    }
  });

  test('VECTEUR FIGÉ : les mêmes octets que le web', () {
    final parts = partagerSecret(secret, 3, 2, alea: coefficients);
    expect(parts.map((p) => '${p.indice}:${_hex(p.valeur)}').toList(), [
      '1:0e50ee6cee08ce8cee60ee4c8e48ee6cee90ce0cce68ee6c0e408e6cee68ce8c',
      '2:01f038567d47a7119228406555bff4822aa0735dadec8c3a82634bd5fe942492',
      '3:049083400c8b80934f10d38b1c1b0bd89fb0189b8c905b080f8b084b07c08b98',
    ]);
  });

  test('deux parts quelconques rendent le secret', () {
    final parts = partagerSecret(secret, 3, 2);
    for (final paire in [
      [0, 1],
      [0, 2],
      [1, 2],
      [2, 0],
    ]) {
      expect(_hex(assemblerSecret([parts[paire[0]], parts[paire[1]]])), _hex(secret));
    }
  });

  test('une part seule, ou deux fois la même, est refusée', () {
    final parts = partagerSecret(secret, 3, 2);
    expect(() => assemblerSecret([parts[0]]), throwsArgumentError);
    expect(() => assemblerSecret([parts[0], parts[0]]), throwsArgumentError);
  });

  test('le parcours entier : partager, sceller, resceller, assembler', () {
    final contact = Curve.generateKeyPair();
    final ephemere = Curve.generateKeyPair();
    final parts = partagerSecret(secret, 3, 2);
    // Le propriétaire scelle la part 2 pour la clé de compte du contact…
    final scellee = emballerCle(parts[1].valeur, Uint8List.fromList(contact.publicKey.serialize()),
        contextePart('alice', 'bob', 1, 1));
    // … le contact l'ouvre et la rescelle pour l'appareil qui demande…
    final valeur = deballerCle(scellee, Uint8List.fromList(contact.privateKey.serialize()),
        contextePart('alice', 'bob', 1, 1));
    final aide = emballerCle(valeur, Uint8List.fromList(ephemere.publicKey.serialize()),
        contexteAide('demande-1', 'alice', parts[1].indice));
    // … qui l'ouvre et l'assemble avec une autre.
    final recue = deballerCle(aide, Uint8List.fromList(ephemere.privateKey.serialize()),
        contexteAide('demande-1', 'alice', parts[1].indice));
    expect(_hex(assemblerSecret([PartShamir(parts[1].indice, recue), parts[2]])), _hex(secret));
    // Assez court pour le serveur (100 à 200 caractères).
    expect(scellee.length, inInclusiveRange(100, 200));
  });
}
