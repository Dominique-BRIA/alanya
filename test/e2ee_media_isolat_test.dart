// UN MÉDIA CHIFFRÉ PART, MÊME QUAND L'ÉCRAN SUIT LA PROGRESSION.
//
// 🐛 « Envoi impossible : object is unsendable - _Future » (user, 04/10/2026).
// Le chiffrement se faisait par un `Isolate.run` écrit dans
// `EnvoiMediaChiffre.envoyer`, à côté d'une fermeture qui capturait le rappel
// de progression de l'écran. Les deux partagent le même contexte : l'isolat
// recevait le rappel, donc l'état du chat, donc un `Future`.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ce que tient l'état d'un écran : un `Future`, impossible à envoyer.
class _EtatEcran {
  final Future<void> chargement = Completer<void>().future;
  double progression = 0;
}

/// L'ANCIENNE FORME, telle qu'elle était dans `EnvoiMediaChiffre.envoyer`.
Future<FichierChiffre> _commeAvant(
  Uint8List octets,
  void Function(double) onProgression,
) async {
  final f = await Isolate.run<FichierChiffre>(() => chiffrerFichier(octets));
  void suivre(int envoyes, int total) => onProgression(envoyes / total);
  suivre(1, 1);
  return f;
}

/// LA FORME CORRIGÉE : même voisinage, mais l'isolat passe par la fonction.
Future<FichierChiffre> _commeMaintenant(
  Uint8List octets,
  void Function(double) onProgression,
) async {
  final f = await chiffrerHorsDuFil(octets);
  void suivre(int envoyes, int total) => onProgression(envoyes / total);
  suivre(1, 1);
  return f;
}

void main() {
  final octets = Uint8List.fromList(List<int>.generate(200000, (i) => i % 251));

  test("l'ancienne forme emporte l'écran dans l'isolat et échoue", () async {
    final ecran = _EtatEcran();
    await expectLater(
      _commeAvant(octets, (r) => ecran.progression = r),
      throwsA(isA<ArgumentError>()),
    );
  });

  test("chiffrerHorsDuFil n'emporte que les octets", () async {
    final ecran = _EtatEcran();
    final f = await _commeMaintenant(octets, (r) => ecran.progression = r);
    expect(ecran.progression, 1);

    final clair = await dechiffrerHorsDuFil(
      f.chiffre,
      cle: f.cle,
      empreinte: f.empreinte,
      taille: octets.length,
    );
    expect(clair, octets);
  });

  test('dechiffrerHorsDuFil rend FichierInvalide sur une empreinte fausse',
      () async {
    final f = await chiffrerHorsDuFil(octets);
    await expectLater(
      dechiffrerHorsDuFil(
        f.chiffre,
        cle: f.cle,
        empreinte: 'AAAA',
        taille: octets.length,
      ),
      throwsA(isA<FichierInvalide>()),
    );
  });
}
