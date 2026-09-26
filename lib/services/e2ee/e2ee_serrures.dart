/// LES SERRURES DE L'ARCHIVE, CÔTÉ MOBILE — ticket 4.14.
///
/// 🔴 JUMEAU DE `STAGE-WEB/src/services/e2ee-serrures.ts`. Le FORMAT doit être
/// identique au chiffre près : une archive créée sur le web doit s'ouvrir sur le
/// téléphone, et l'inverse. Sel de 16 octets, IV de 12, clé maîtresse de 32,
/// AES-GCM, paramètres rangés en JSON avec la serrure.
///
/// ⚠️ CE FORMAT EST IDENTIQUE PAR CONSTRUCTION, PAS ENCORE PAR MESURE. Le banc
/// d'interopérabilité éprouve le protocole Signal et le QR ; il ne fait pas
/// encore passer une archive d'un client à l'autre. C'est la prochaine chose à
/// prouver — et tant qu'elle ne l'est pas, on ne promet rien.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// D'où vient le secret qui ouvre une serrure.
enum TypeSerrure { trousseau, motdepasse, recuperation }

/// Une serrure, telle qu'elle se range sur le serveur.
class Serrure {
  const Serrure({
    required this.type,
    required this.sel,
    required this.iv,
    required this.cleEnveloppee,
    required this.algo,
    required this.parametres,
    this.appareil = '',
  });

  final String type;
  final String sel;
  final String iv;
  final String cleEnveloppee;
  final String algo;
  final String parametres;

  /// ⚠️ VIDE SAUF POUR LE TROUSSEAU. Un mot de passe et une clé de récupération
  /// suivent la PERSONNE ; un trousseau appartient à UN APPAREIL. Le serveur
  /// porte cette règle par une contrainte, et la refuse autrement.
  final String appareil;

  Map<String, dynamic> enJson() => {
        'type': type,
        'sel': sel,
        'iv': iv,
        'cleEnveloppee': cleEnveloppee,
        'algo': algo,
        'parametres': parametres,
        'appareil': appareil,
      };

  static Serrure depuisJson(Map<String, dynamic> j) => Serrure(
        type: j['type'] as String,
        sel: j['sel'] as String,
        iv: j['iv'] as String,
        cleEnveloppee: j['cleEnveloppee'] as String,
        algo: j['algo'] as String,
        parametres: j['parametres'] as String,
        appareil: (j['appareil'] as String?) ?? '',
      );
}

/// Le réglage de dérivation, PAR TYPE DE SECRET.
///
/// 🔴 CE N'EST PAS UNE CONSTANTE UNIQUE, et c'est le point le plus subtil du
/// fichier. L'étirement compense le MANQUE D'ENTROPIE d'un secret :
///
///   · un mot de passe humain vaut peut-être 30 bits → il faut l'étirer, cher ;
///   · un secret de 256 bits tiré au sort ne se devine PAS → l'étirer ne protège
///     de rien et coûte une seconde à celui qui déverrouille son téléphone.
///
/// ⚠️ APPLIQUER LE RÉGLAGE FORT PARTOUT est l'erreur la plus fréquente : on paie
/// une protection inutile, on croit avoir mieux fait, et cela pousse à réduire
/// là où ça compte.
({String algo, Map<String, int> parametres}) reglagePour(TypeSerrure t) {
  switch (t) {
    case TypeSerrure.motdepasse:
      /*
       * ⚠️ ARGON2ID, ET NON PBKDF2, pour le seul secret qui se devine. PBKDF2 se
       * parallélise sur carte graphique ; Argon2id exige de la MÉMOIRE — 64 Mio
       * par essai — ce qu'une carte graphique ne multiplie pas à l'infini. C'est
       * exactement la menace : quelqu'un qui a emporté une copie de la base.
       */
      return (
        algo: 'argon2id',
        parametres: {'memoireKio': 65536, 'passes': 3, 'parallelisme': 1},
      );
    case TypeSerrure.trousseau:
    case TypeSerrure.recuperation:
      // 256 bits tirés au sort : une itération suffit, et ce n'est pas une
      // négligence.
      return (algo: 'pbkdf2-sha256', parametres: {'iterations': 1});
  }
}

final _sort = Random.secure();

Uint8List _auHasard(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _sort.nextInt(256)));

/// Dérive la clé qui enveloppe — la KEK.
Uint8List _kek(String secret, Uint8List sel, String algo, Map<String, dynamic> p) {
  final octets = Uint8List.fromList(utf8.encode(secret));

  if (algo == 'argon2id') {
    final g = Argon2BytesGenerator()
      ..init(Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        sel,
        version: Argon2Parameters.ARGON2_VERSION_13,
        iterations: p['passes'] as int,
        memory: p['memoireKio'] as int,
        lanes: p['parallelisme'] as int,
        // ⚠️ 32 OCTETS, comme la clé maîtresse et comme le web. Une longueur
        // différente donnerait une KEK incompatible, sans erreur explicite.
        desiredKeyLength: 32,
      ));
    return g.process(octets);
  }

  final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(sel, p['iterations'] as int, 32));
  return d.process(octets);
}

/// Enveloppe la clé maîtresse, ou la désenveloppe.
///
/// ⚠️ PAS DE HACHÉ DE VÉRIFICATION rangé à côté. AES-GCM authentifie : un mauvais
/// secret fait échouer le déchiffrement, et c'est LE contrôle. En ranger un
/// offrirait une cible à casser hors ligne, sans même toucher à l'archive.
Uint8List _gcm(Uint8List cle, Uint8List iv, Uint8List entree, bool chiffrer) {
  final c = GCMBlockCipher(AESEngine())
    ..init(chiffrer, AEADParameters(KeyParameter(cle), 128, iv, Uint8List(0)));
  return c.process(entree);
}

/// Crée une archive : une clé maîtresse neuve, et une serrure par secret.
///
/// 🔴 LA CLÉ QUI CHIFFRE L'ARCHIVE EST TIRÉE AU SORT, jamais dérivée d'un
/// secret. C'est ce qui permet de l'envelopper autant de fois qu'on veut — et
/// de changer de mot de passe en ré-enveloppant 32 octets au lieu de rechiffrer
/// toute l'archive.
({Uint8List maitresse, List<Serrure> serrures}) creerArchive(
  Map<TypeSerrure, String> secrets, {
  String appareil = '',
}) {
  final maitresse = _auHasard(32);
  final serrures = <Serrure>[];

  secrets.forEach((type, secret) {
    serrures.add(poserSerrure(maitresse, type, secret, appareil: appareil));
  });

  return (maitresse: maitresse, serrures: serrures);
}

/// Pose une serrure sur une clé maîtresse déjà connue.
Serrure poserSerrure(
  Uint8List maitresse,
  TypeSerrure type,
  String secret, {
  String appareil = '',
}) {
  final r = reglagePour(type);
  final sel = _auHasard(16);
  final iv = _auHasard(12);
  final kek = _kek(secret, sel, r.algo, r.parametres);

  return Serrure(
    type: type.name,
    sel: base64.encode(sel),
    iv: base64.encode(iv),
    cleEnveloppee: base64.encode(_gcm(kek, iv, maitresse, true)),
    algo: r.algo,
    parametres: jsonEncode(r.parametres),
    appareil: type == TypeSerrure.trousseau ? appareil : '',
  );
}

/// Ouvre l'archive avec un secret.
///
/// ⚠️ LÈVE SI LE SECRET EST MAUVAIS, et c'est AES-GCM qui le dit. Il n'y a pas
/// de cas où la clé serait bonne et le déchiffrement échouerait : chercher une
/// autre cause fait perdre du temps.
Uint8List ouvrirArchive(String secret, Serrure s) {
  final kek = _kek(
    secret,
    Uint8List.fromList(base64.decode(s.sel)),
    s.algo,
    jsonDecode(s.parametres) as Map<String, dynamic>,
  );
  return _gcm(
    kek,
    Uint8List.fromList(base64.decode(s.iv)),
    Uint8List.fromList(base64.decode(s.cleEnveloppee)),
    false,
  );
}

/* ══════════════ LA CLÉ DE RÉCUPÉRATION ══════════════ */

/// ⚠️ SANS ACCENT NI CARACTÈRE AMBIGU : elle sera recopiée à la main, sur un
/// carnet, peut-être par quelqu'un qui n'a pas de clavier français.
///
/// 🐛 CETTE LISTE A ÉTÉ ALIGNÉE SUR CELLE DU WEB APRÈS COUP. J'en avais écrit
/// une autre — 36 mots différents — en affirmant dans un commentaire qu'elle
/// était identique. Elle ne l'était pas.
///
/// ⚠️ ET L'AFFIRMATION ELLE-MÊME ÉTAIT FAUSSE : deux dictionnaires différents ne
/// rendraient PAS une clé illisible d'un client à l'autre. Le secret est la
/// CHAÎNE DE MOTS elle-même, pas un indice dans une liste — n'importe quelle
/// suite de mots ouvre la serrure si elle est exacte. La liste ne sert qu'à
/// TIRER une clé, jamais à la relire.
///
/// On l'aligne quand même, pour que les deux clients produisent des clés de même
/// nature — et parce qu'un commentaire faux dans un fichier de cryptographie est
/// plus dangereux que pas de commentaire.
const List<String> motsRecuperation = [
  'tortue', 'riviere', 'lampe', 'cousin', 'fenetre', 'orage',
  'sable', 'guitare', 'renard', 'marbre', 'pluie', 'cerise',
  'montagne', 'velours', 'hibou', 'bambou', 'falaise', 'encrier',
  'girafe', 'menthe', 'tambour', 'nuage', 'corail', 'pivoine',
  'safran', 'brume', 'loutre', 'cypres', 'silex', 'harpe',
  'jonquille', 'ocean',
];

/// Tire une clé de récupération : 12 mots parmi 32, soit 60 bits.
///
/// 🐛 J'AVAIS ÉCRIT QUE 60 BITS ÉTAIENT INSUFFISANTS. C'est faux, et le web
/// l'explique mieux : ce secret n'étant pas étiré, sa force EST sa seule
/// protection — et soixante bits résistent à une attaque hors ligne pour un coût
/// qui dépasse de très loin l'intérêt d'une archive de messagerie personnelle.
///
/// ⚠️ LES PORTER À 128 FERAIT VINGT-QUATRE MOTS À RECOPIER, et c'est le papier
/// perdu qui deviendrait le vrai risque. Durcir un chiffre sans regarder ce
/// qu'il coûte ailleurs n'est pas une amélioration.
String tirerCleRecuperation() =>
    List.generate(12, (_) => motsRecuperation[_sort.nextInt(motsRecuperation.length)])
        .join(' ');

/// Nettoie une saisie recopiée à la main.
///
/// ⚠️ MAJUSCULES, ESPACES EN TROP, RETOUR À LA LIGNE : c'est ainsi qu'elle
/// arrivera vraiment. Refuser pour cela ferait perdre l'archive pour une raison
/// qui n'a rien à voir avec la sécurité.
String normaliserCleRecuperation(String saisie) =>
    saisie.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

/* ══════════════ LE CONTENU DE L'ARCHIVE ══════════════ */

/// Un IV neuf, à chaque bloc.
///
/// 🔴 JAMAIS RÉUTILISÉ. Deux blocs chiffrés avec le même IV et la même clé
/// laissent AES-GCM s'effondrer : leur différence révèle la différence des
/// clairs. C'est la faute la plus classique de ce mode, et la plus grave.
Uint8List ivNeuf() => _auHasard(12);

/// Chiffre un bloc d'archive avec la clé maîtresse.
Uint8List chiffrerAvec(Uint8List maitresse, Uint8List iv, Uint8List clair) =>
    _gcm(maitresse, iv, clair, true);

/// Déchiffre un bloc d'archive.
///
/// ⚠️ LÈVE SI LE BLOC A ÉTÉ TOUCHÉ : AES-GCM authentifie. L'appelant compte le
/// bloc comme illisible plutôt que de rendre des octets douteux.
Uint8List dechiffrerAvec(Uint8List maitresse, Uint8List iv, Uint8List chiffre) =>
    _gcm(maitresse, iv, chiffre, false);
