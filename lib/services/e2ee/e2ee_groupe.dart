/// CHIFFREMENT DES GROUPES — le trousseau de groupe (lot 1).
///
/// Conception : `backend-alanya/docs/2026-10-08-e2ee-groupes-conception.md`,
/// § 2. Cours : chapitres 31 et 32. JUMEAU EXACT de
/// `STAGE-WEB/src/services/e2ee-groupe.ts` : un octet de différence, et un
/// message du téléphone ne se lit plus sur le web. Les vecteurs
/// `test/donnees/vecteur_groupe_*.json` tiennent les deux.
///
///   · une clé de groupe par VERSION, 32 octets tirés au hasard ;
///   · un message chiffré UNE fois (AES-256-GCM), lié à son contexte par des
///     données associées, et SIGNÉ par l'appareil expéditeur (XEdDSA) ;
///   · le trousseau (toutes les versions) voyage dans une enveloppe Signal à
///     deux, sous la charge « G1 ».
///
/// ⚠️ DART PUR, sans Flutter : se teste hors application, et sert aussi à
/// `tool/vecteur_groupe_mobile.dart`.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:pointycastle/export.dart';

/// Le seul format de message de groupe connu.
const formatGroupe = 0x01;

/// Préfixe de la charge « trousseau » : un caractère nul, impossible à taper.
const prefixeTrousseau = '\u0000G1';

const _tailleCle = 32;
const _tailleNonce = 12;
const _tailleEtiquette = 16;
const _tailleSignature = 64;

/// Un message de groupe ou un trousseau refusé : on le dit, on ne devine pas.
class GroupeInvalide implements Exception {
  const GroupeInvalide(this.message);
  final String message;
  @override
  String toString() => 'GroupeInvalide: $message';
}

/// Tout ce qui lie un chiffré à SA place.
class ContexteGroupe {
  const ContexteGroupe({
    required this.convId,
    required this.messageId,
    required this.version,
    required this.expediteurId,
    required this.deviceId,
  });
  final String convId;
  final String messageId;
  final int version;
  final String expediteurId;
  final int deviceId;
}

/* ══════════════════ OUTILS ══════════════════ */

Uint8List _concat(List<Uint8List> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.takeBytes();
}

Uint8List _aleatoire(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

/* ══════════════════ LA SIGNATURE ══════════════════ */

/// Signe [message] avec la clé PRIVÉE d'identité de cet appareil (32 octets).
Uint8List signer(Uint8List clePrivee, Uint8List message) =>
    Curve.calculateSignature(Curve.decodePrivatePoint(clePrivee), message);

/// La signature est-elle VALIDE ?
///
/// ⚠️ ICI, `Curve.verifySignature` rend bien `true` pour une signature
/// VALIDE. Ce n'est PAS le cas sur le web, où la même fonction rend `true`
/// pour une signature INVALIDE (cours, chapitre 32). Les deux jumeaux exposent
/// donc `signatureValide`, au sens sans ambiguïté, et les vecteurs croisés
/// contiennent une signature falsifiée, refusée des deux côtés.
bool signatureValide(Uint8List clePublique, Uint8List message, Uint8List signature) {
  if (signature.length != _tailleSignature) return false;
  try {
    return Curve.verifySignature(Curve.decodePoint(clePublique, 0), message, signature);
  } catch (_) {
    // Clé publique mal formée : pas une signature valide.
    return false;
  }
}

/* ══════════════════ LA CLÉ ET LE MESSAGE ══════════════════ */

/// Une clé de groupe neuve : 32 octets du générateur sûr.
Uint8List genererCleGroupe() => _aleatoire(_tailleCle);

/// Les données associées : ce qui colle le chiffré à SA place. Voir le jumeau
/// web pour le choix du séparateur.
Uint8List donneesAssociees(ContexteGroupe c) {
  for (final v in [c.convId, c.messageId, c.expediteurId]) {
    if (v.isEmpty || v.contains('\n')) throw const GroupeInvalide('contexte mal formé');
  }
  if (c.version < 1) throw const GroupeInvalide('version invalide');
  if (c.deviceId < 0) throw const GroupeInvalide('appareil invalide');
  return Uint8List.fromList(utf8.encode(
    'alanya-groupe-v1\n${c.convId}\n${c.messageId}\n${c.version}\n'
    '${c.expediteurId}\n${c.deviceId}',
  ));
}

Uint8List _gcm(bool chiffrer, Uint8List cle, Uint8List nonce, Uint8List aad, Uint8List entree) {
  final c = GCMBlockCipher(AESEngine())
    ..init(chiffrer, AEADParameters(KeyParameter(cle), 128, nonce, aad));
  return c.process(entree);
}

/// Chiffre et signe un message de groupe. [clair] est la charge v2 du
/// message, inchangée (`ecrireCharge`, e2ee_media.dart).
///
/// Rend `base64( 0x01 | nonce(12) | chiffré+étiquette | signature(64) )`.
///
/// [nonceImpose] n'existe que pour les vecteurs : un nonce réutilisé avec la
/// même clé détruit la confidentialité de GCM.
String chiffrerMessageGroupe(
  String clair,
  Uint8List cle,
  ContexteGroupe contexte,
  Uint8List clePriveeIdentite, {
  Uint8List? nonceImpose,
}) {
  if (cle.length != _tailleCle) throw const GroupeInvalide('clé de groupe invalide');
  final aad = donneesAssociees(contexte);
  final nonce = nonceImpose ?? _aleatoire(_tailleNonce);
  if (nonce.length != _tailleNonce) throw const GroupeInvalide('nonce invalide');
  final chiffre = _gcm(true, cle, nonce, aad, Uint8List.fromList(utf8.encode(clair)));
  final signature = signer(clePriveeIdentite, _concat([aad, nonce, chiffre]));
  return base64Encode(
      _concat([Uint8List.fromList([formatGroupe]), nonce, chiffre, signature]));
}

/// Vérifie PUIS déchiffre un message de groupe. Lève [GroupeInvalide].
///
/// [clePubliqueIdentite] : la clé d'identité de l'appareil expéditeur TELLE
/// QUE CET APPAREIL LA CONNAÎT DÉJÀ (session à deux) — jamais une clé
/// redemandée au serveur pour l'occasion.
///
/// ⚠️ LA SIGNATURE D'ABORD : on ne fait rien du contenu d'un inconnu.
String dechiffrerMessageGroupe(
  String corps,
  Uint8List cle,
  ContexteGroupe contexte,
  Uint8List clePubliqueIdentite,
) {
  final Uint8List brut;
  try {
    brut = base64Decode(corps);
  } catch (_) {
    throw const GroupeInvalide('corps illisible');
  }
  if (brut.length < 1 + _tailleNonce + _tailleEtiquette + _tailleSignature) {
    throw const GroupeInvalide('corps trop court');
  }
  if (brut[0] != formatGroupe) throw const GroupeInvalide('format inconnu');
  if (cle.length != _tailleCle) throw const GroupeInvalide('clé de groupe invalide');

  final nonce = Uint8List.sublistView(brut, 1, 1 + _tailleNonce);
  final chiffre =
      Uint8List.sublistView(brut, 1 + _tailleNonce, brut.length - _tailleSignature);
  final signature = Uint8List.sublistView(brut, brut.length - _tailleSignature);
  final aad = donneesAssociees(contexte);

  if (!signatureValide(clePubliqueIdentite, _concat([aad, nonce, chiffre]), signature)) {
    throw const GroupeInvalide('signature refusée : expéditeur ou contenu falsifié');
  }
  try {
    return utf8.decode(_gcm(false, cle, nonce, aad, chiffre));
  } catch (_) {
    throw const GroupeInvalide(
        'déchiffrement refusé : mauvaise clé, mauvaise version ou contexte déplacé');
  }
}

/* ══════════════════ LA CHARGE « TROUSSEAU » ══════════════════ */

const motifsTrousseau = {'ACTIVATION', 'AJOUT', 'EXCLUSION', 'MANUEL', 'APPAREIL'};

class VersionCle {
  const VersionCle({required this.n, required this.cle, required this.creeLe});
  final int n;
  final Uint8List cle;

  /// Millisecondes depuis 1970.
  final int creeLe;
}

class Trousseau {
  const Trousseau({required this.convId, required this.motif, required this.versions});
  final String convId;
  final String motif;
  final List<VersionCle> versions;
}

/// Le clair à chiffrer pour transmettre un trousseau, d'appareil à appareil.
///
/// ⚠️ ORDRE DES CHAMPS FIXE, et le même que le web : les vecteurs comparent
/// les deux chaînes octet pour octet. Versions triées par numéro.
String ecrireChargeTrousseau(Trousseau t) {
  final versions = [...t.versions]..sort((a, b) => a.n.compareTo(b.n));
  return prefixeTrousseau +
      jsonEncode({
        'v': 1,
        'type': 'trousseau',
        'convId': t.convId,
        'motif': t.motif,
        'versions': [
          for (final x in versions)
            {'n': x.n, 'cle': base64Encode(x.cle), 'creeLe': x.creeLe},
        ],
      });
}

/// Ce clair est-il un trousseau ? (Avant d'essayer de le lire.)
bool estChargeTrousseau(String clair) => clair.startsWith(prefixeTrousseau);

/* ══════════════════ LA DEMANDE DE TROUSSEAU (repli APPAREIL) ══════════════════ */

/// Préfixe d'une DEMANDE de trousseau, envoyée par un appareil à SES AUTRES
/// appareils quand une clé lui manque (cours, chapitre 37). Jumeau du web.
const prefixeDemande = '\u0000GD';

String ecrireDemandeTrousseau(String convId) =>
    prefixeDemande + jsonEncode({'v': 1, 'type': 'demande-trousseau', 'convId': convId});

bool estDemandeTrousseau(String clair) => clair.startsWith(prefixeDemande);

/// Lit une demande et rend le groupe visé — celui de l'enveloppe.
String lireDemandeTrousseau(String clair, String convIdEnveloppe) {
  if (!estDemandeTrousseau(clair)) throw const GroupeInvalide('pas une demande de trousseau');
  Object? brut;
  try {
    brut = jsonDecode(clair.substring(prefixeDemande.length));
  } catch (_) {
    throw const GroupeInvalide('demande illisible');
  }
  if (brut is! Map || brut['v'] != 1 || brut['type'] != 'demande-trousseau') {
    throw const GroupeInvalide('demande mal formée');
  }
  if (brut['convId'] != convIdEnveloppe) {
    throw const GroupeInvalide('demande rattachée à un autre groupe que le sien');
  }
  return convIdEnveloppe;
}

/// Lit et VÉRIFIE une charge trousseau. Voir le jumeau web.
Trousseau lireChargeTrousseau(String clair, String convIdEnveloppe) {
  if (!estChargeTrousseau(clair)) throw const GroupeInvalide('pas une charge trousseau');
  Object? brut;
  try {
    brut = jsonDecode(clair.substring(prefixeTrousseau.length));
  } catch (_) {
    throw const GroupeInvalide('trousseau illisible');
  }
  if (brut is! Map || brut['v'] != 1 || brut['type'] != 'trousseau') {
    throw const GroupeInvalide('trousseau mal formé');
  }
  if (brut['convId'] is! String || brut['convId'] != convIdEnveloppe) {
    throw const GroupeInvalide('trousseau rattaché à un autre groupe que le sien');
  }
  if (!motifsTrousseau.contains(brut['motif'])) throw const GroupeInvalide('motif inconnu');
  final liste = brut['versions'];
  if (liste is! List || liste.isEmpty) throw const GroupeInvalide('trousseau vide');
  final vues = <int>{};
  final versions = <VersionCle>[];
  for (final x in liste) {
    if (x is! Map) throw const GroupeInvalide('version mal formée');
    final n = x['n'];
    if (n is! int || n < 1) throw const GroupeInvalide('numéro de version invalide');
    if (!vues.add(n)) throw const GroupeInvalide('version en double');
    final cleB64 = x['cle'];
    if (cleB64 is! String) throw const GroupeInvalide('clé absente');
    final Uint8List cle;
    try {
      cle = base64Decode(cleB64);
    } catch (_) {
      throw const GroupeInvalide('clé illisible');
    }
    if (cle.length != _tailleCle) throw const GroupeInvalide('clé de mauvaise taille');
    final creeLe = x['creeLe'];
    if (creeLe is! num) throw const GroupeInvalide('date invalide');
    versions.add(VersionCle(n: n, cle: cle, creeLe: creeLe.toInt()));
  }
  versions.sort((a, b) => a.n.compareTo(b.n));
  return Trousseau(
      convId: brut['convId'] as String, motif: brut['motif'] as String, versions: versions);
}

/// Fusionne un trousseau reçu dans celui qu'on a.
///
/// 🔴 UNE VERSION DÉJÀ CONNUE AVEC UNE AUTRE CLÉ EST REFUSÉE : personne ne
/// doit pouvoir REMPLACER une clé existante. Voir le jumeau web.
List<VersionCle> fusionnerTrousseau(List<VersionCle> connu, List<VersionCle> recu) {
  final parN = {for (final v in connu) v.n: v};
  for (final v in recu) {
    final deja = parN[v.n];
    if (deja != null) {
      if (base64Encode(deja.cle) != base64Encode(v.cle)) {
        throw GroupeInvalide('la version ${v.n} est déjà connue avec une autre clé');
      }
      continue;
    }
    parN[v.n] = v;
  }
  return parN.values.toList()..sort((a, b) => a.n.compareTo(b.n));
}

/* ══════════════════ LA BOÎTE PERMANENTE (chapitre 39) ══════════════════ */

/// La BOÎTE : le trousseau d'un groupe, scellé pour UN appareil et gardé par le
/// serveur ; l'appareil la relit quand il veut, sans administrateur en ligne
/// (décision du user, 10/10/2026). Jumeau de `scellerBoite` / `ouvrirBoite`
/// côté web — même forme, mêmes données associées (vecteurs croisés).
///
///   corps = base64( 0x01 | éphémère 33 | nonce 12 | AES-256-GCM | signature 64 )
///   clé   = HKDF-SHA256( X25519(éphémère, identité du destinataire),
///                        sel = 32 zéros, info = « alanya-boite-v1 » )
const formatBoite = 0x01;
const _infoBoite = 'alanya-boite-v1';
const _taillePublique = 33;

class ContexteBoite {
  const ContexteBoite({
    required this.convId,
    required this.destinataireId,
    required this.destinataireDevice,
    required this.expediteurId,
    required this.expediteurDevice,
  });
  final String convId;
  final String destinataireId;
  final int destinataireDevice;
  final String expediteurId;
  final int expediteurDevice;
}

Uint8List donneesBoite(ContexteBoite c) {
  for (final v in [c.convId, c.destinataireId, c.expediteurId]) {
    if (v.isEmpty || v.contains('\n')) throw const GroupeInvalide('contexte de boîte mal formé');
  }
  if (c.destinataireDevice < 0 || c.expediteurDevice < 0) {
    throw const GroupeInvalide('appareil invalide');
  }
  return Uint8List.fromList(utf8.encode('$_infoBoite\n${c.convId}\n${c.destinataireId}\n'
      '${c.destinataireDevice}\n${c.expediteurId}\n${c.expediteurDevice}'));
}

Uint8List _cleDeBoite(Uint8List partage) {
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(partage, 32, Uint8List(32), Uint8List.fromList(utf8.encode(_infoBoite))));
  final sortie = Uint8List(32);
  hkdf.deriveKey(null, 0, sortie, 0);
  return sortie;
}

/// Scelle [clair] pour l'appareil dont la clé publique d'identité est
/// [clePubliqueDestinataire] (33 octets), et signe avec [clePriveeExpediteur].
/// [ephemere] et [nonceImpose] : pour les vecteurs seulement.
String scellerBoite(
  String clair,
  Uint8List clePubliqueDestinataire,
  ContexteBoite contexte,
  Uint8List clePriveeExpediteur, {
  ({Uint8List pub, Uint8List priv})? ephemere,
  Uint8List? nonceImpose,
}) {
  final eph = ephemere ??
      (() {
        final k = Curve.generateKeyPair();
        return (pub: Uint8List.fromList(k.publicKey.serialize()), priv: Uint8List.fromList(k.privateKey.serialize()));
      })();
  final partage = Curve.calculateAgreement(
      Curve.decodePoint(clePubliqueDestinataire, 0), Curve.decodePrivatePoint(eph.priv));
  final nonce = nonceImpose ?? _aleatoire(_tailleNonce);
  final aad = donneesBoite(contexte);
  final chiffre = _gcm(true, _cleDeBoite(partage), nonce, aad, Uint8List.fromList(utf8.encode(clair)));
  final signature = signer(clePriveeExpediteur, _concat([aad, eph.pub, nonce, chiffre]));
  return base64.encode(_concat([Uint8List.fromList([formatBoite]), eph.pub, nonce, chiffre, signature]));
}

/// Ouvre une boîte : signature d'abord (identité DÉJÀ connue de l'expéditeur),
/// déchiffrement ensuite. Lève [GroupeInvalide].
String ouvrirBoite(
  String corps,
  Uint8List clePriveeDestinataire,
  ContexteBoite contexte,
  Uint8List clePubliqueExpediteur,
) {
  final Uint8List brut;
  try {
    brut = base64.decode(corps);
  } catch (_) {
    throw const GroupeInvalide('boîte illisible');
  }
  const min = 1 + _taillePublique + _tailleNonce + _tailleEtiquette + _tailleSignature;
  if (brut.length < min || brut[0] != formatBoite) throw const GroupeInvalide('boîte mal formée');
  final eph = Uint8List.sublistView(brut, 1, 1 + _taillePublique);
  final nonce = Uint8List.sublistView(brut, 1 + _taillePublique, 1 + _taillePublique + _tailleNonce);
  final chiffre =
      Uint8List.sublistView(brut, 1 + _taillePublique + _tailleNonce, brut.length - _tailleSignature);
  final signature = Uint8List.sublistView(brut, brut.length - _tailleSignature);
  final aad = donneesBoite(contexte);
  if (!signatureValide(clePubliqueExpediteur, _concat([aad, eph, nonce, chiffre]), signature)) {
    throw const GroupeInvalide('boîte : signature invalide');
  }
  try {
    final partage = Curve.calculateAgreement(
        Curve.decodePoint(eph, 0), Curve.decodePrivatePoint(clePriveeDestinataire));
    return utf8.decode(_gcm(false, _cleDeBoite(partage), nonce, aad, chiffre));
  } catch (_) {
    throw const GroupeInvalide('boîte : déchiffrement refusé');
  }
}
