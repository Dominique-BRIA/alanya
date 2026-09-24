/// LE CÔTÉ MOBILE DU BANC D'INTEROPÉRABILITÉ.
///
/// 🔴 CE PROGRAMME NE CONSTRUIT PAS D'APK, ET C'EST TOUT SON INTÉRÊT. Il est en
/// Dart PUR : il tourne sur la machine de développement, en quelques secondes,
/// et éprouve la seule chose qui puisse encore remettre en cause le lot 4 —
/// est-ce que la bibliothèque du mobile et celle du web se comprennent ?
///
/// ⚠️ CE QU'IL NE PROUVE PAS : que l'application Flutter marche. Il n'y a ici ni
/// interface, ni coffre matériel, ni réseau. Ce qu'il prouve, c'est le FORMAT
/// SUR LE FIL — et c'est justement ce qui ne se rattrape pas si l'on se trompe.
///
/// Usage : dart run bin/mobile.dart <etape> <fichier-entree> <fichier-sortie>
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:pointycastle/digests/sha512.dart';

/// Les magasins de Bob, gardés d'une étape à l'autre par un fichier.
///
/// ⚠️ UN VRAI CLIENT LES RANGERAIT DANS LE COFFRE MATÉRIEL (Android Keystore,
/// iOS Keychain). Ici on les sérialise en clair sur le disque : c'est un banc,
/// et le rappeler évite qu'on recopie ce code dans l'application.
class Bob {
  Bob(this.identite, this.registrationId, this.preKey, this.signedPreKey);

  final IdentityKeyPair identite;
  final int registrationId;
  final PreKeyRecord preKey;
  final SignedPreKeyRecord signedPreKey;

  static Bob creer() {
    final identite = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    final preKeys = generatePreKeys(0, 1);
    final signed = generateSignedPreKey(identite, 0);
    return Bob(identite, registrationId, preKeys.first, signed);
  }

  Map<String, dynamic> enJson() => {
        'identite': base64.encode(identite.serialize()),
        'registrationId': registrationId,
        'preKey': base64.encode(preKey.serialize()),
        'signedPreKey': base64.encode(signedPreKey.serialize()),
      };

  static Bob depuisJson(Map<String, dynamic> j) => Bob(
        IdentityKeyPair.fromSerialized(base64.decode(j['identite'] as String)),
        j['registrationId'] as int,
        PreKeyRecord.fromBuffer(base64.decode(j['preKey'] as String)),
        SignedPreKeyRecord.fromSerialized(
            base64.decode(j['signedPreKey'] as String)),
      );
}

/// Le paquet public que le serveur distribue — celui que le web ira chercher.
///
/// 🔴 C'EST ICI QUE L'INTEROPÉRABILITÉ SE JOUE. Si les deux bibliothèques
/// n'encodent pas les clés de la même façon — 33 octets préfixés par `0x05`
/// pour Curve25519 — rien ne marchera, et l'erreur ressemblera à « mauvaise
/// signature » plutôt qu'à « mauvais format ».
Map<String, dynamic> bundlePublic(Bob bob) => {
      'registrationId': bob.registrationId,
      'deviceId': 1,
      'preKeyId': bob.preKey.id,
      'preKeyPublic': base64.encode(bob.preKey.getKeyPair().publicKey.serialize()),
      'signedPreKeyId': bob.signedPreKey.id,
      'signedPreKeyPublic':
          base64.encode(bob.signedPreKey.getKeyPair().publicKey.serialize()),
      'signedPreKeySignature': base64.encode(bob.signedPreKey.signature),
      'identityKey': base64.encode(bob.identite.getPublicKey().serialize()),
    };

Future<
    ({
      SessionCipher cipher,
      InMemorySessionStore sessions,
    })> montageBob(Bob bob, SignalProtocolAddress alice) async {
  final sessions = InMemorySessionStore();
  final preKeys = InMemoryPreKeyStore();
  final signed = InMemorySignedPreKeyStore();
  final identites = InMemoryIdentityKeyStore(bob.identite, bob.registrationId);

  await preKeys.storePreKey(bob.preKey.id, bob.preKey);
  await signed.storeSignedPreKey(bob.signedPreKey.id, bob.signedPreKey);

  return (
    cipher: SessionCipher(sessions, preKeys, signed, identites, alice),
    sessions: sessions,
  );
}

Future<void> main(List<String> args) async {
  final etape = args[0];
  final entree = args.length > 1 && args[1].isNotEmpty
      ? jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  final sortie = args.length > 2 ? args[2] : '';

  Map<String, dynamic> resultat;

  switch (etape) {
    /// ① Bob se présente : le serveur publierait ceci.
    case 'publier':
      final bob = Bob.creer();
      resultat = {
        'secret': bob.enJson(),
        'bundle': bundlePublic(bob),
      };

    /// ③ Bob déchiffre ce qu'Alice (le web) lui a envoyé.
    ///
    /// ⚠️ C'EST UN `PreKeySignalMessage` — le tout premier message d'une
    /// session, celui qui porte le matériel X3DH. S'il passe, l'accord de clés
    /// entre les deux bibliothèques est prouvé.
    case 'dechiffrer':
      final bob = Bob.depuisJson(entree['secret'] as Map<String, dynamic>);
      final alice = const SignalProtocolAddress('alice', 1);
      final m = await montageBob(bob, alice);

      final chiffre = base64.decode(entree['corps'] as String);
      final clair = await m.cipher
          .decrypt(PreKeySignalMessage(Uint8List.fromList(chiffre)));

      /// ④ Et Bob répond dans la foulée, sur la session ainsi ouverte.
      final reponse = await m.cipher
          .encrypt(Uint8List.fromList(utf8.encode(entree['reponse'] as String)));

      resultat = {
        'clair': utf8.decode(clair),
        'reponseType': reponse.getType(),
        'reponseCorps': base64.encode(reponse.serialize()),
      };

    /// Le code de sécurité, calculé côté mobile.
    ///
    /// 🔴 LA BIBLIOTHÈQUE DART N'A PAS DE CLASSE `Fingerprint`. On réimplémente
    /// donc l'algorithme de Signal — 5 200 itérations de SHA-512 — et ce banc
    /// vérifie que le résultat correspond AU CHIFFRE PRÈS à celui du web.
    ///
    /// ⚠️ SI LES DEUX DIVERGENT, les utilisateurs comparent des codes
    /// différents pour les mêmes clés et concluent à une interposition qui
    /// n'existe pas. C'est un défaut qui détruit la confiance sans qu'aucune
    /// clé n'ait fuité.
    case 'empreinte':
      resultat = {
        'empreinte': await empreinte(
          base64.decode(entree['cleLocale'] as String),
          utf8.encode(entree['idLocal'] as String),
          base64.decode(entree['cleDistante'] as String),
          utf8.encode(entree['idDistant'] as String),
        ),
      };

    default:
      throw ArgumentError('étape inconnue : $etape');
  }

  final texte = const JsonEncoder.withIndent('  ').convert(resultat);
  if (sortie.isEmpty) {
    stdout.writeln(texte);
  } else {
    File(sortie).writeAsStringSync(texte);
  }
}

/// L'algorithme d'empreinte de Signal, réécrit.
///
/// ⚠️ LES 5 200 ITÉRATIONS NE SE CHOISISSENT PAS : c'est le nombre de Signal, et
/// deux clients qui n'itèrent pas pareil produisent des codes différents. C'est
/// un paramètre d'INTEROPÉRABILITÉ autant que de sécurité.
Future<String> empreinte(
  List<int> cleLocale,
  List<int> idLocal,
  List<int> cleDistante,
  List<int> idDistant,
) async {
  final a = await moitie(cleLocale, idLocal);
  final b = await moitie(cleDistante, idDistant);
  // ⚠️ TRIÉES : les deux correspondants doivent lire la MÊME chaîne, quel que
  // soit celui qui regarde son écran.
  final deux = [a, b]..sort();
  return deux.join();
}

Future<String> moitie(List<int> cle, List<int> identifiant) async {
  const iterations = 5200;
  final version = [0x00, 0x00];

  var donnee = <int>[...version, ...cle, ...identifiant];
  for (var i = 0; i < iterations; i++) {
    donnee = sha512(<int>[...donnee, ...cle]);
  }

  // Cinq groupes de cinq chiffres, tirés de 30 octets.
  final sortie = StringBuffer();
  for (var i = 0; i < 6; i++) {
    final morceau = donnee.sublist(i * 5, i * 5 + 5);
    var n = 0;
    for (final o in morceau) {
      n = (n << 8) | o;
    }
    sortie.write((n % 100000).toString().padLeft(5, '0'));
  }
  return sortie.toString();
}

List<int> sha512(List<int> entree) {
  final d = SHA512Digest();
  final sortie = Uint8List(64);
  d.update(Uint8List.fromList(entree), 0, entree.length);
  d.doFinal(sortie, 0);
  return sortie;
}
