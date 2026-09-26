/// LE CHIFFREMENT DE BOUT EN BOUT, CÔTÉ MOBILE.
///
/// 🔴 CE FICHIER EST LE JUMEAU DE `STAGE-WEB/src/services/e2ee-service.ts`. Les
/// deux clients parlent le même protocole — c'est prouvé par le banc
/// d'interopérabilité (`alanya/interop`, ticket 4.0) : le web chiffre, le mobile
/// déchiffre, et l'inverse.
///
/// ⚠️ CE QUI N'EST PAS ENCORE ÉPROUVÉ : ce fichier-ci, sur un vrai téléphone.
/// L'APK n'est pas construit localement. Le PROTOCOLE est prouvé ; l'intégration
/// Flutter — coffre matériel, réseau, cycle de vie — ne l'est pas.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:pointycastle/digests/sha512.dart';

import 'e2ee_coffre.dart';

/// Combien de pré-clés à usage unique on publie d'un coup.
///
/// ⚠️ C'EST UN STOCK QUI S'ÉPUISE. Chacune ne sert qu'une fois : sans
/// réapprovisionnement, X3DH saute son quatrième calcul Diffie-Hellman — la
/// session reste valide mais perd une garantie. Le web réapprovisionne sous 10 ;
/// le mobile suit la même règle.
const int lotPreKeys = 50;
const int seuilReappro = 10;

class E2eeService {
  E2eeService(this.coffre, this.api);

  final CoffreE2ee coffre;

  /// L'accès réseau, injecté — ce service ne connaît pas votre client HTTP.
  ///
  /// ⚠️ INJECTÉ PLUTÔT QU'IMPORTÉ : c'est ce qui rend ce fichier testable en
  /// Dart pur, sans Flutter ni serveur. Le banc d'interopérabilité s'en sert.
  final Future<Map<String, dynamic>> Function(
    String methode,
    String chemin,
    Map<String, dynamic>? corps,
  ) api;

  /* ══════════════ PUBLIER SES CLÉS ══════════════ */

  /// Prépare cet appareil et publie ses clés publiques.
  ///
  /// 🔴 SEULES DES CLÉS PUBLIQUES SORTENT D'ICI. Si une clé privée passait par
  /// cette fonction, tout l'édifice serait faux — c'est le contrôle à faire en
  /// relecture avant tout autre.
  Future<void> publierMesCles({required int deviceId}) async {
    await coffre.preparer();

    final identite = await coffre.identiteLocale();

    /*
     * 🔴 LA SIGNÉE EST RÉUTILISÉE, PAS RÉGÉNÉRÉE. La version précédente
     * fabriquait une matière neuve sous le MÊME identifiant à chaque
     * démarrage : tout correspondant qui avait retiré la liasse avant le
     * redémarrage préparait son message avec une publique dont la privée
     * venait d'être jetée — indéchiffrable à l'arrivée.
     */
    final signedId = await coffre.idPrekeySignee();
    final signeeNouvelle = !await coffre.containsSignedPreKey(signedId);
    final signee = signeeNouvelle
        ? generateSignedPreKey(identite, signedId)
        : await coffre.loadSignedPreKey(signedId);
    if (signeeNouvelle) {
      await coffre.storeSignedPreKey(signee.id, signee);
    }

    /*
     * 🔴 LES UNIQUES SONT RÉASSORTIES, PAS REMPLACÉES. On complète le stock
     * jusqu'au lot avec des identifiants FRAIS — jamais réutilisés, voir
     * `CoffreE2ee.prochainIdPrekey` — et on ne touche pas à celles qui
     * restent : des correspondants les tiennent peut-être déjà.
     */
    final existants = await coffre.idsPrekeysUniques();
    var prochain = await coffre.prochainIdPrekey();
    if (existants.isNotEmpty) {
      final maxExistant = existants.reduce((a, b) => a > b ? a : b);
      if (prochain <= maxExistant) prochain = maxExistant + 1;
    }
    final manque = lotPreKeys - existants.length;
    final nouvelles = <PreKeyRecord>[];
    if (manque > 0) {
      for (final p in generatePreKeys(prochain, manque)) {
        await coffre.storePreKey(p.id, p);
        nouvelles.add(p);
      }
      await coffre.reglerProchainIdPrekey(prochain + manque);
    }

    final dejaPublie = await coffre.aPublie();
    if (dejaPublie && !signeeNouvelle && nouvelles.isEmpty) {
      // ℹ️ RIEN DE NEUF : le serveur tient déjà ce stock à l'identique, et
      // le lui renvoyer en entier à chaque démarrage accumulerait des
      // doublons s'il ajoute au lieu de remplacer.
      return;
    }

    /*
     * ⚠️ AU PREMIER ENVOI, TOUT LE STOCK — ensuite, SEULEMENT LE NOUVEAU.
     * Le premier envoi doit fournir le lot complet ; les suivants ne disent
     * que ce qui a changé, comme un réassort.
     */
    final aEnvoyer = <PreKeyRecord>[];
    if (!dejaPublie) {
      for (final id in existants) {
        aEnvoyer.add(await coffre.loadPreKey(id));
      }
    }
    aEnvoyer.addAll(nouvelles);

    await api('POST', '/api/e2ee/cles', {
      'deviceId': deviceId,
      'registrationId': await coffre.getLocalRegistrationId(),
      'cleIdentite': base64.encode(identite.getPublicKey().serialize()),
      'prekeySignee': {
        'prekeyId': signee.id,
        'clePublique': base64.encode(signee.getKeyPair().publicKey.serialize()),
        'signature': base64.encode(signee.signature),
      },
      'prekeysUniques': aEnvoyer
          .map((p) => {
                'prekeyId': p.id,
                'clePublique':
                    base64.encode(p.getKeyPair().publicKey.serialize()),
              })
          .toList(),
    });
    await coffre.noterPublication();
  }

  /* ══════════════ OUVRIR UNE SESSION ══════════════ */

  /// Les appareils chiffrés d'un correspondant, SANS ouvrir de session.
  ///
  /// 🔴 SANS EFFET DE BORD, contrairement à [ouvrirSessions] : traiter une
  /// liasse installe une session, ce que la vérification du code n'a pas à
  /// faire — elle lit, elle ne négocie pas.
  Future<List<int>> appareilsDe(String pairId) async {
    final r = await api('GET', '/api/e2ee/cles/$pairId', null);
    final paquets = ((r['appareils'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return [for (final p in paquets) p['deviceId'] as int];
  }

  /// Ouvre une session vers chaque appareil du correspondant.
  ///
  /// ⚠️ UNE SESSION PAR APPAREIL, PAS PAR PERSONNE. Bob peut avoir un téléphone
  /// et un navigateur ; un message doit être chiffré séparément pour chacun,
  /// sinon l'un des deux ne le lira jamais.
  Future<List<int>> ouvrirSessions(String pairId) async {
    final r = await api('GET', '/api/e2ee/cles/$pairId', null);
    // ⚠️ `appareils` ABSENT = personne à qui écrire, pas une erreur de
    // contrat : un compte sans clés publiées rend une liste vide, et c'est
    // l'appelant qui décide — voir `E2eeFil.envoyer`.
    final paquets = ((r['appareils'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final ouverts = <int>[];

    for (final p in paquets) {
      final adresse = SignalProtocolAddress(pairId, p['deviceId'] as int);
      final signee = p['prekeySignee'] as Map<String, dynamic>;
      final unique = p['prekeyUnique'] as Map<String, dynamic>?;

      final bundle = PreKeyBundle(
        p['registrationId'] as int,
        p['deviceId'] as int,
        // ⚠️ `-1` quand le stock est épuisé : la bibliothèque saute alors la
        // pré-clé unique, ce qui reste valide mais affaiblit la session.
        unique == null ? -1 : unique['prekeyId'] as int,
        unique == null
            ? null
            : Curve.decodePoint(
                base64.decode(unique['clePublique'] as String), 0),
        signee['prekeyId'] as int,
        Curve.decodePoint(base64.decode(signee['clePublique'] as String), 0),
        base64.decode(signee['signature'] as String),
        IdentityKey.fromBytes(base64.decode(p['cleIdentite'] as String), 0),
      );

      /*
       * 🔴 `processPreKeyBundle` VÉRIFIE LA SIGNATURE de la pré-clé signée avec
       * la clé d'identité. C'est LE contrôle qui écarte un serveur servant une
       * pré-clé fabriquée. On laisse l'exception remonter : une session qu'on
       * n'a pas pu vérifier ne doit pas s'ouvrir.
       */
      await SessionBuilder.fromSignalStore(coffre, adresse)
          .processPreKeyBundle(bundle);
      ouverts.add(p['deviceId'] as int);
    }
    return ouverts;
  }

  /* ══════════════ CHIFFRER / DÉCHIFFRER ══════════════ */

  /// Chiffre un texte pour un appareil donné.
  Future<({int type, String corps})> chiffrer(
    String pairId,
    int deviceId,
    String texte,
  ) async {
    final adresse = SignalProtocolAddress(pairId, deviceId);
    final chiffreur = SessionCipher.fromStore(coffre, adresse);
    final e = await chiffreur.encrypt(
      Uint8List.fromList(utf8.encode(texte)),
    );
    return (type: e.getType(), corps: base64.encode(e.serialize()));
  }

  /// Déchiffre une enveloppe.
  ///
  /// ⚠️ DEUX FORMES, ET IL FAUT LES DISTINGUER : le PREMIER message d'une
  /// session porte le matériel X3DH (type 3) et s'ouvre autrement que les
  /// suivants (type 1). Se tromper donne une erreur de déchiffrement qui fait
  /// chercher du côté des clés alors que le format seul est en cause.
  Future<String> dechiffrer(
    String pairId,
    int deviceId,
    int type,
    String corpsB64,
  ) async {
    final adresse = SignalProtocolAddress(pairId, deviceId);
    final chiffreur = SessionCipher.fromStore(coffre, adresse);
    final brut = Uint8List.fromList(base64.decode(corpsB64));

    final clair = type == CiphertextMessage.prekeyType
        ? await chiffreur.decrypt(PreKeySignalMessage(brut))
        : await chiffreur.decryptFromSignal(SignalMessage.fromSerialized(brut));

    return utf8.decode(clair);
  }

  /* ══════════════ LE CODE DE SÉCURITÉ ══════════════ */

  /// L'empreinte à comparer de vive voix.
  ///
  /// 🔴 RÉÉCRITE À LA MAIN : la bibliothèque Dart n'a pas de classe
  /// `Fingerprint`. Le banc d'interopérabilité vérifie qu'elle rend EXACTEMENT
  /// le même code que le web, au chiffre près.
  ///
  /// ⚠️ LES 5 200 ITÉRATIONS NE SE CHOISISSENT PAS. C'est le nombre de Signal :
  /// deux clients qui n'itèrent pas pareil affichent des codes différents pour
  /// les mêmes clés, et les gens concluent à une interposition qui n'existe pas.
  /// C'est un paramètre d'INTEROPÉRABILITÉ autant que de sécurité.
  ///
  /// ⚠️ ON LIT LA CLÉ DU COFFRE LOCAL, jamais celle que le serveur annonce. Un
  /// serveur interposé montrerait la vraie clé de Bob pendant qu'il fait parler
  /// Alice à un imposteur : le code correspondrait, et la vérification aurait
  /// prouvé exactement rien.
  Future<String> codeSecurite({
    required String monId,
    required String pairId,
    required SignalProtocolAddress adressePair,
  }) async {
    final moi = (await coffre.identiteLocale()).getPublicKey().serialize();
    final lui = (await coffre.getIdentity(adressePair))?.serialize();
    if (lui == null) {
      throw StateError('Aucune clé connue pour ce correspondant.');
    }

    final a = _moitie(moi, utf8.encode(monId));
    final b = _moitie(lui, utf8.encode(pairId));
    // ⚠️ TRIÉES : les deux correspondants doivent lire la MÊME chaîne, quel que
    // soit celui qui regarde son écran.
    return ([a, b]..sort()).join();
  }

  /// Un code par appareil chiffré du correspondant.
  ///
  /// 🔴 UNE IDENTITÉ PAR APPAREIL, DONC UN CODE PAR APPAREIL. Le téléphone et
  /// le navigateur du pair n'ont rien en commun : un seul code pour les deux
  /// obligerait à en inventer un, que personne d'autre ne calculerait pareil.
  ///
  /// ⚠️ CEUX QU'ON NE PEUT PAS CALCULER SONT SAUTÉS, pas remplacés par une
  /// erreur : une session existe par appareil, et on peut avoir écrit au
  /// téléphone sans jamais avoir écrit au navigateur. Un plan vide veut dire
  /// « aucune clé connue », et c'est l'écran qui le dit.
  Future<Map<int, String>> codesSecurite({
    required String monId,
    required String pairId,
  }) async {
    final codes = <int, String>{};
    for (final appareil in await appareilsDe(pairId)) {
      try {
        codes[appareil] = await codeSecurite(
          monId: monId,
          pairId: pairId,
          adressePair: SignalProtocolAddress(pairId, appareil),
        );
      } catch (_) {
        // Pas de session avec cet appareil — on passe au suivant.
      }
    }
    return codes;
  }

  String _moitie(List<int> cle, List<int> identifiant) {
    var donnee = <int>[0x00, 0x00, ...cle, ...identifiant];
    for (var i = 0; i < 5200; i++) {
      donnee = _sha512(<int>[...donnee, ...cle]);
    }
    final sortie = StringBuffer();
    for (var i = 0; i < 6; i++) {
      var n = 0;
      for (final o in donnee.sublist(i * 5, i * 5 + 5)) {
        n = (n << 8) | o;
      }
      sortie.write((n % 100000).toString().padLeft(5, '0'));
    }
    return sortie.toString();
  }

  /* ══════════════ LE QR DE VÉRIFICATION ══════════════ */

  /// Ce que le QR code contient.
  ///
  /// 🔴 IL ENCODE LE CODE LUI-MÊME, RIEN D'AUTRE — décision, pas raccourci.
  /// Signal encode les deux clés d'identité dans un format binaire ; nous
  /// encodons les 60 chiffres DÉJÀ AFFICHÉS.
  ///
  /// ⚠️ POURQUOI C'EST PLUS SÛR ICI : deux formats différents — l'un pour l'œil,
  /// l'autre pour la caméra — peuvent DIVERGER. Le défaut ne se verrait qu'au
  /// moment où quelqu'un essaie vraiment de vérifier, c'est-à-dire quand il
  /// s'inquiète. En scannant exactement ce qui est écrit, la divergence devient
  /// impossible par construction.
  ///
  /// ⚠️ LE QR N'AJOUTE AUCUNE SÉCURITÉ, seulement de la COMMODITÉ : comparer
  /// soixante chiffres à l'œil est pénible et on se trompe. La garantie reste la
  /// même — il faut être EN FACE, hors du canal qu'on vérifie. Un QR reçu PAR la
  /// conversation ne prouve rien, exactement comme un code recopié.
  static String qrDepuisCode(String code) => 'alanya-e2ee:1:$code';

  /// Relit un QR scanné et rend le code, ou `null` s'il n'est pas des nôtres.
  ///
  /// ⚠️ ON REFUSE CE QU'ON NE RECONNAÎT PAS. Scanner le QR d'une autre
  /// application et afficher « ne correspond pas » ferait croire à une
  /// interposition là où il n'y a qu'un mauvais QR.
  static String? codeDepuisQr(String contenu) {
    final parts = contenu.split(':');
    if (parts.length != 3 || parts[0] != 'alanya-e2ee' || parts[1] != '1') {
      return null;
    }
    final code = parts[2];
    // Six groupes de cinq chiffres — la forme de l'empreinte de Signal.
    return RegExp(r'^[0-9]{60}$').hasMatch(code) ? code : null;
  }

  List<int> _sha512(List<int> entree) {
    final d = SHA512Digest();
    final sortie = Uint8List(64);
    d.update(Uint8List.fromList(entree), 0, entree.length);
    d.doFinal(sortie, 0);
    return sortie;
  }
}
