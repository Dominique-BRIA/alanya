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
import 'dart:math';
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

/// Lit une liste dans une réponse du serveur, en NOMMANT ce qui manque.
///
/// 🔴 UN `as List` NU DIT « Null n'est pas List<dynamic> » ET RIEN D'AUTRE.
/// Ni quel champ, ni quelle route, ni quel appel. C'est le message qui s'est
/// affiché en production — impossible à relier à quoi que ce soit sans lire le
/// code ligne à ligne.
///
/// ⚠️ LES NOMS DE CHAMPS SONT LE TROU QUE `outils/contrat_routes.py` NE
/// COUVRE PAS : il vérifie le verbe et le chemin, pas le contenu. Tant que ce
/// contrôle n'existe pas, le moins qu'on doive faire est d'échouer en disant
/// QUOI.
List<Map<String, dynamic>> listeDe(Map<String, dynamic> reponse, String champ) {
  final v = reponse[champ];
  if (v is! List) {
    throw StateError(
      "Le serveur n'a pas rendu « $champ » "
      '(reçu : ${v.runtimeType}, champs présents : ${reponse.keys.join(", ")})',
    );
  }
  return v.cast<Map<String, dynamic>>();
}

class E2eeService {
  E2eeService(this.coffre, this.api);

  /* ══════════════ UN SEUL ACCÈS AU COFFRE À LA FOIS ══════════════ */

  /// La file des opérations qui ÉCRIVENT dans le coffre.
  ///
  /// 🔴 LE COFFRE N'A AUCUN VERROU, ET IL EN FAUT UN. Il range ses pré-clés et
  /// ses sessions sous forme de TABLES ENTIÈRES : chaque écriture relit la
  /// table, la modifie, la réécrit. Deux opérations entrelacées — un envoi et
  /// une relève sur le même correspondant, une relève et un réapprovisionnement
  /// — écrivent chacune leur version, et la dernière efface l'autre : un cliquet
  /// qui recule, ou cinquante pré-clés publiées dont la clé privée n'existe plus.
  ///
  /// ⚠️ LE WEB N'EN A PAS BESOIN : sa bibliothèque sérialise elle-même les
  /// opérations par correspondant (`SessionLock`). Celle du mobile ne le fait
  /// pas.
  ///
  /// ⚠️ AUCUNE DE CES MÉTHODES N'EN APPELLE UNE AUTRE : ce serait attendre son
  /// propre tour, et ne jamais l'obtenir.
  Future<void> _file = Future<void>.value();

  Future<T> _enSerie<T>(Future<T> Function() operation) {
    final tour = _file.then((_) => operation());
    _file = tour.then((_) {}, onError: (_) {});
    return tour;
  }

  Future<void> publierMesCles({required int deviceId}) =>
      _enSerie(() => _publierMesCles(deviceId: deviceId));

  Future<List<int>> ouvrirSessions(String pairId) =>
      _enSerie(() => _ouvrirSessions(pairId));

  Future<void> oublierSession(String pairId, int deviceId) =>
      _enSerie(() => _oublierSession(pairId, deviceId));

  Future<({int type, String corps})> chiffrer(
    String pairId,
    int deviceId,
    String texte,
  ) =>
      _enSerie(() => _chiffrer(pairId, deviceId, texte));

  Future<String> dechiffrer(
    String pairId,
    int deviceId,
    int type,
    String corpsB64,
  ) =>
      _enSerie(() => _dechiffrer(pairId, deviceId, type, corpsB64));

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
  /// ⚠️ LES IDENTIFIANTS SONT TIRÉS AU SORT, ET CE N'EST PAS COSMÉTIQUE.
  ///
  /// 🐛 Ils partaient de zéro : `generatePreKeys(0, 50)` rendait toujours
  /// 0…50. Republier un lot produisait donc EXACTEMENT les mêmes numéros, et
  /// le serveur les écarte (`skipDuplicates`) — sans erreur, sans message. Le
  /// stock ne se serait jamais reconstitué, et rien ne l'aurait dit.
  ///
  /// La borne reprend celle du web : le protocole veut un entier moyen, pas un
  /// entier 64 bits.
  int _idAuHasard() => Random.secure().nextInt(100000) + 1;

  Future<void> _publierMesCles({required int deviceId}) async {
    await coffre.preparer();

    final identite = await coffre.identiteLocale();
    final signee = generateSignedPreKey(identite, _idAuHasard());
    await coffre.storeSignedPreKey(signee.id, signee);

    final uniques = generatePreKeys(_idAuHasard(), lotPreKeys);
    for (final p in uniques) {
      await coffre.storePreKey(p.id, p);
    }

    /*
     * 🔴 `PUT`, ET NON `POST` — ET C'EST LA CAUSE D'UNE PANNE ENTIÈRE.
     *
     * 🐛 La route `/api/e2ee/cles` n'exporte que `GET`, `PUT` et `DELETE`. Un
     * `POST` recevait donc 405, et le mobile n'a JAMAIS publié la moindre clé.
     * Personne ne pouvait lui écrire — en ligne ou non.
     *
     * ⚠️ ET LES NOMS DE CHAMPS DIVERGEAIENT AUSSI : le serveur lit `prekeys`
     * et `id`, pas `prekeysUniques` et `prekeyId`. Trois erreurs sur le même
     * appel, dont aucune n'était visible : `dart analyze` ne connaît pas les
     * routes, et le banc d'interopérabilité branche une fausse fonction
     * réseau — il éprouve le PROTOCOLE, jamais le CONTRAT HTTP.
     */
    await api('PUT', '/api/e2ee/cles', {
      'deviceId': deviceId,
      'registrationId': await coffre.getLocalRegistrationId(),
      'cleIdentite': base64.encode(identite.getPublicKey().serialize()),
      'prekeySignee': {
        'id': signee.id,
        'clePublique': base64.encode(signee.getKeyPair().publicKey.serialize()),
        'signature': base64.encode(signee.signature),
      },
      'prekeys': uniques
          .map((p) => {
                'id': p.id,
                'clePublique':
                    base64.encode(p.getKeyPair().publicKey.serialize()),
              })
          .toList(),
    });
  }

  /// Republie un lot si le SERVEUR dit que le stock est bas.
  ///
  /// 🐛 LE SERVEUR RÉCLAMAIT DÉJÀ, ET LE MOBILE N'ÉCOUTAIT PAS.
  /// `GET /api/e2ee/cles` rend `reapproNecessaire` depuis le premier jour ; le
  /// web s'en sert, le mobile l'ignorait.
  ///
  /// ⚠️ CE QUE ÇA DONNAIT : les 50 pré-clés à usage unique s'épuisent au fil
  /// des nouveaux correspondants, et le jour où il n'en reste plus, PLUS
  /// PERSONNE ne peut ouvrir de conversation avec cet appareil. Panne muette :
  /// rien ne casse chez celui qui la subit, ce sont les AUTRES qui n'arrivent
  /// plus à lui écrire.
  ///
  /// ⚠️ C'EST LE SERVEUR QUI RÉCLAME, PAS LE CLIENT QUI DEVINE. Deux appareils
  /// consomment le même stock : un client qui compterait tout seul se
  /// tromperait dès le second.
  ///
  /// ⚠️ NE LÈVE JAMAIS. C'est un entretien de fond ; l'échouer ne doit pas
  /// empêcher d'envoyer le message qu'on est en train d'écrire.
  Future<bool> reapprovisionnerSiNecessaire({required int deviceId}) async {
    try {
      final etat = await api('GET', '/api/e2ee/cles', null);
      final appareils = (etat['appareils'] as List?) ?? const [];
      for (final a in appareils) {
        final m = a as Map<String, dynamic>;
        if (m['deviceId'] != deviceId) continue;
        if (m['reapproNecessaire'] != true) return false;
        /*
         * ⚠️ ON REPASSE PAR `publierMesCles`, ON NE DUPLIQUE PAS. Elle publie
         * un lot neuf ET fait tourner la pré-clé signée. Un second chemin
         * « juste pour les pré-clés » divergerait le jour où l'un changerait.
         *
         * ⚠️ ELLE NE REGÉNÈRE PAS L'IDENTITÉ : `preparer()` sort si elle
         * existe. C'est ce qui rend ce rappel sans danger.
         */
        await publierMesCles(deviceId: deviceId);
        return true;
      }
      return false;
    } catch (_) {
      // Réseau coupé, serveur ancien : on réessaiera au prochain démarrage.
      return false;
    }
  }

  /* ══════════════ OUVRIR UNE SESSION ══════════════ */

  /// Ouvre une session vers chaque appareil du correspondant.
  ///
  /// ⚠️ UNE SESSION PAR APPAREIL, PAS PAR PERSONNE. Bob peut avoir un téléphone
  /// et un navigateur ; un message doit être chiffré séparément pour chacun,
  /// sinon l'un des deux ne le lira jamais.
  Future<List<int>> _ouvrirSessions(String pairId) async {
    final r = await api('GET', '/api/e2ee/cles/$pairId', null);
    /*
     * 🐛 LE CHAMP S'APPELLE `paquets`, PAS `appareils`. On lisait le mauvais
     * nom : la valeur était `null`, et le `as List` levait un
     * `_TypeError: type 'Null' is not a subtype of type 'List<dynamic>'` —
     * illisible pour qui le reçoit, et muet sur ce qui manque.
     *
     * ⚠️ `GET /api/e2ee/cles` (mes appareils) rend bien `appareils` ; c'est
     * `GET /api/e2ee/cles/<compte>` (le paquet d'un correspondant) qui rend
     * `paquets`. Deux routes voisines, deux noms — et rien pour le rappeler.
     */
    final paquets = listeDe(r, 'paquets');
    final ouverts = <int>[];

    for (final p in paquets) {
      final adresse = SignalProtocolAddress(pairId, p['deviceId'] as int);

      /*
       * 🔴 UNE SESSION QUI EXISTE NE SE REFAIT PAS. C'ÉTAIT LE CAS, À CHAQUE
       * ENVOI, ET C'EST UNE FAUTE DE PROTOCOLE.
       *
       * 🐛 `processPreKeyBundle` REMPLACE la session. On l'appelait sans
       * regarder s'il y en avait une : chaque message repartait donc d'un
       * X3DH neuf, consommait une pré-clé du correspondant, et surtout
       * ORPHELINAIT la session que lui avait de son côté.
       *
       * ⚠️ UNE SESSION SIGNAL EST UN ÉTAT À DEUX. Un seul des deux ne peut pas
       * la refaire dans son coin : ses messages ordinaires deviennent
       * indéchiffrables pour l'autre, en silence et définitivement.
       *
       * 🐛 C'est ce qui s'est produit en ouvrant l'écran de vérification : il
       * appelle `ouvrirSessions` pour pouvoir calculer le code, ce qui
       * remplaçait la session — et les messages suivants du correspondant,
       * chiffrés avec l'ancienne, n'étaient plus lisibles.
       *
       * ⚠️ LE RATCHET EST FAIT POUR DURER. Le refaire à chaque message annule
       * ce qu'il apporte et coûte une pré-clé à chaque fois.
       */
      if (await coffre.containsSession(adresse)) {
        ouverts.add(p['deviceId'] as int);
        continue;
      }

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

  /// Jette la session d'un correspondant pour que la prochaine reparte à neuf.
  ///
  /// ⚠️ À N'APPELER QUE SUR UN ÉCHEC DE DÉCHIFFREMENT. Une session qui marche
  /// ne se jette pas : la refaire coûte une pré-clé au correspondant et
  /// orpheline la sienne. C'est exactement la faute qu'on vient de corriger
  /// dans `ouvrirSessions`.
  Future<void> _oublierSession(String pairId, int deviceId) =>
      coffre.deleteSession(SignalProtocolAddress(pairId, deviceId));

  /* ══════════════ CHIFFRER / DÉCHIFFRER ══════════════ */

  /// Chiffre un texte pour un appareil donné.
  Future<({int type, String corps})> _chiffrer(
    String pairId,
    int deviceId,
    String texte,
  ) async {
    final adresse = SignalProtocolAddress(pairId, deviceId);
    final chiffreur = SessionCipher.fromStore(coffre, adresse);
    final e = await chiffreur.encrypt(
      Uint8List.fromList(utf8.encode(texte)),
    );
    return (type: _typeSurLeFil(e.getType()), corps: base64.encode(e.serialize()));
  }

  /// Traduit le type de la bibliothèque Dart vers celui du FIL.
  ///
  /// 🔴 LES DEUX BIBLIOTHÈQUES NE NUMÉROTENT PAS PAREIL, ET PERSONNE NE L'AVAIT
  /// REMARQUÉ :
  ///
  /// ```
  ///   libsignal_protocol_dart   whisperType = 2   prekeyType = 3
  ///   libsignal-protocol-ts     WHISPER     = 1   PREKEY     = 3
  /// ```
  ///
  /// 🐛 Le mobile posait donc **2** sur le fil pour un message ordinaire. Le
  /// serveur n'accepte que 1 ou 3 et répondait 400 « enveloppe mal formée » :
  /// le PREMIER message d'une session passait (type 3), tous les suivants
  /// tombaient.
  ///
  /// ⚠️ LE BANC D'INTEROPÉRABILITÉ NE POUVAIT PAS LE VOIR. Son faux serveur
  /// RELAYAIT le nombre sans le valider, et le web traite tout ce qui n'est pas
  /// 3 comme un message ordinaire — donc 2 fonctionnait entre les deux
  /// bibliothèques. Seul le vrai serveur, qui contrôle, refusait.
  ///
  /// 🔴 C'EST LE FIL QUI FAIT FOI, PAS LA BIBLIOTHÈQUE. Le format d'échange est
  /// celui du web et du serveur ; chaque client traduit à sa frontière. Aligner
  /// le serveur sur le Dart aurait cassé le web, et l'inverse était impossible.
  ///
  /// ⚠️ LA RÉCEPTION N'A RIEN À TRADUIRE : `dechiffrer` ne teste que « est-ce
  /// 3 ? », ce qui vaut des deux côtés.
  static int _typeSurLeFil(int type) =>
      type == CiphertextMessage.prekeyType ? 3 : 1;

  /// Déchiffre une enveloppe.
  ///
  /// ⚠️ DEUX FORMES, ET IL FAUT LES DISTINGUER : le PREMIER message d'une
  /// session porte le matériel X3DH (type 3) et s'ouvre autrement que les
  /// suivants (type 1). Se tromper donne une erreur de déchiffrement qui fait
  /// chercher du côté des clés alors que le format seul est en cause.
  Future<String> _dechiffrer(
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
