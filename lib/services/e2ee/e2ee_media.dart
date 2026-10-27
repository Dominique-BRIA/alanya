/// MÉDIAS CHIFFRÉS DE BOUT EN BOUT — le format, et le chiffrement des fichiers.
///
/// JUMEAU EXACT de `STAGE-WEB/src/services/e2ee-media.ts` (voir ce fichier pour
/// le raisonnement complet, et le chapitre 23 du cours). Un octet de
/// différence, et un média envoyé du web ne s'ouvre plus ici. Le vecteur
/// `test/donnees/vecteur_media.json`, produit par le web, tient les deux.
///
/// ⚠️ DART PUR, sans Flutter : ce fichier s'exécute dans un isolat
/// (`Isolate.run`) pour qu'une vidéo de 50 Mo ne fige pas l'écran, et se teste
/// hors application.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'agb1_natif.dart';

// ════════════════════════════════════════════════════════════════════════════
// 1. LA CHARGE DE L'ENVELOPPE
// ════════════════════════════════════════════════════════════════════════════

/// Préfixe d'une charge v2 : un caractère nul, impossible à taper.
const prefixeChargeV2 = '\u0000A2';

/// Ce qu'il faut savoir d'un média pour l'afficher, l'ouvrir et le vérifier.
class DescripteurMedia {
  const DescripteurMedia({
    required this.id,
    required this.cle,
    required this.empreinte,
    required this.taille,
    required this.mime,
    this.nom,
    this.largeur,
    this.hauteur,
    this.dureeMs,
    this.pages,
    this.apercu,
    this.sensible = false,
    this.protection,
  });

  /// Identifiant du média sur le serveur.
  final String id;

  /// Clé AES-256, base64 (32 octets).
  final String cle;

  /// SHA-256 du fichier CHIFFRÉ, base64.
  final String empreinte;

  /// Taille du fichier EN CLAIR.
  final int taille;

  /// Type réel — le serveur ne voit que `application/octet-stream`.
  final String mime;
  final String? nom;
  final int? largeur;
  final int? hauteur;
  final int? dureeMs;
  final int? pages;

  /// Aperçu JPEG en base64.
  final String? apercu;

  /// DOCUMENT SENSIBLE (18/10/2026) : il s'ouvre seulement dans l'application,
  /// avec un filigrane (numéro Alanya, appareil, date et heure), écran protégé,
  /// et ne se transfère ni ne se partage. Écrit SEULEMENT s'il est vrai : un
  /// descripteur ordinaire ne change pas d'un octet (vecteur partagé avec le web).
  final bool sensible;

  /// La PROTECTION d'un PDF sensible (24/10/2026) : voir [ProtectionPdf].
  /// Écrite seulement si elle existe — même raison que [sensible].
  final ProtectionPdf? protection;

  Map<String, dynamic> toJson() => {
    'id': id,
    'cle': cle,
    'empreinte': empreinte,
    'taille': taille,
    'mime': mime,
    if (nom != null) 'nom': nom,
    if (largeur != null) 'largeur': largeur,
    if (hauteur != null) 'hauteur': hauteur,
    if (dureeMs != null) 'dureeMs': dureeMs,
    if (pages != null) 'pages': pages,
    if (apercu != null) 'apercu': apercu,
    if (sensible) 'sensible': true,
    if (protection != null) 'protection': protection!.toJson(),
  };

  /// Lit un descripteur, et le REFUSE s'il est mal formé — jamais de valeur
  /// par défaut inventée pour une clé ou une empreinte.
  static DescripteurMedia depuisJson(Object? brut) {
    if (brut is! Map)
      throw const ChargeInvalide('descripteur de média mal formé');
    String chaine(String c) {
      final v = brut[c];
      if (v is! String || v.isEmpty) {
        throw ChargeInvalide('descripteur : « $c » manquant');
      }
      return v;
    }

    int? entier(String c) {
      final v = brut[c];
      if (v == null) return null;
      if (v is! int || v < 0)
        throw ChargeInvalide('descripteur : « $c » invalide');
      return v;
    }

    final taille = brut['taille'];
    if (taille is! int || taille < 0) {
      throw const ChargeInvalide('descripteur : taille invalide');
    }
    final d = DescripteurMedia(
      id: chaine('id'),
      cle: chaine('cle'),
      empreinte: chaine('empreinte'),
      taille: taille,
      mime: chaine('mime'),
      nom: brut['nom'] is String ? brut['nom'] as String : null,
      largeur: entier('largeur'),
      hauteur: entier('hauteur'),
      dureeMs: entier('dureeMs'),
      pages: entier('pages'),
      apercu: brut['apercu'] is String ? brut['apercu'] as String : null,
      sensible: brut['sensible'] == true,
      protection: brut['protection'] == null
          ? null
          : ProtectionPdf.depuisJson(brut['protection']),
    );
    if (_b64(d.cle)?.length != 32)
      throw const ChargeInvalide('clé de média invalide');
    if (_b64(d.empreinte)?.length != 32) {
      throw const ChargeInvalide('empreinte de média invalide');
    }
    return d;
  }
}

/// LA PROTECTION D'UN PDF SENSIBLE (24/10/2026, demande du user).
///
/// L'expéditeur la règle une fois, à l'envoi : autoriser l'impression ou non,
/// mettre un mot de passe ou non — et s'il en met un, il en saisit DEUX :
///
/// * [ouverture] : celui qu'il faut pour ouvrir la copie téléchargée. Montré
///   en clair à l'expéditeur, en VUE UNIQUE au destinataire ;
/// * [proprietaire] : celui qui lève les restrictions (l'impression). Montré à
///   l'expéditeur seulement.
///
/// Sans mot de passe mais sans impression, [proprietaire] est tiré au hasard
/// par l'appareil qui envoie : une restriction de PDF n'existe qu'avec un mot
/// de passe propriétaire. Personne ne le voit.
///
/// 🔴 ELLE VOYAGE DANS L'ENVELOPPE CHIFFRÉE, jamais en clair : le serveur ne
/// voit pas les mots de passe. Elle s'applique à la COPIE qui sort
/// d'Alanya (`SignatureDocument`) ; dans l'application, le document reste
/// lisible dans la visionneuse protégée.
class ProtectionPdf {
  const ProtectionPdf({
    required this.imprimer,
    required this.proprietaire,
    this.ouverture,
  });

  /// La copie peut-elle s'imprimer sans le mot de passe propriétaire ?
  final bool imprimer;

  /// Le mot de passe d'ouverture, `null` sans mot de passe.
  final String? ouverture;

  /// Le mot de passe propriétaire, toujours présent.
  final String proprietaire;

  bool get avecMotDePasse => ouverture != null;

  /// Un mot de passe propriétaire que personne ne saisit : 24 caractères tirés
  /// par le générateur sûr du système.
  static String proprietaireAuHasard([Random? hasard]) {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final r = hasard ?? Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 24; i++) alphabet.codeUnitAt(r.nextInt(alphabet.length)),
    ]);
  }

  Map<String, dynamic> toJson() => {
    'imprimer': imprimer,
    if (ouverture != null) 'ouverture': ouverture,
    'proprietaire': proprietaire,
  };

  static ProtectionPdf depuisJson(Object? brut) {
    if (brut is! Map) throw const ChargeInvalide('protection mal formée');
    final imprimer = brut['imprimer'];
    final ouverture = brut['ouverture'];
    final proprietaire = brut['proprietaire'];
    if (imprimer is! bool ||
        proprietaire is! String ||
        proprietaire.isEmpty ||
        (ouverture != null && (ouverture is! String || ouverture.isEmpty))) {
      throw const ChargeInvalide('protection mal formée');
    }
    return ProtectionPdf(
      imprimer: imprimer,
      ouverture: ouverture as String?,
      proprietaire: proprietaire,
    );
  }
}

/// Ce que porte une enveloppe une fois ouverte.
class Charge {
  const Charge({
    required this.texte,
    this.media,
    this.idAnnonce,
    this.reponseA,
    this.genre,
    this.modifie = false,
  });
  final String texte;
  final DescripteurMedia? media;

  /// L'identifiant chiffré par l'expéditeur (v2), `null` pour un texte v1.
  final String? idAnnonce;

  /// Le message AUQUEL CELUI-CI RÉPOND (06/10/2026), dans le chiffré comme
  /// l'identifiant : le serveur ne peut pas faire répondre un message à un
  /// autre. Seul l'identifiant voyage — le texte cité est relu sur l'appareil.
  final String? reponseA;

  /// `CONTACT` ou `LOCATION` : [texte] porte alors la fiche JSON (06/10/2026).
  /// `null` pour un texte ou un média.
  final String? genre;

  /// Le NOUVEAU texte d'un message déjà envoyé (07/10/2026, cours ch. 29) :
  /// il remplace l'ancien, là où une enveloppe ordinaire ne remplit qu'une
  /// bulle vide.
  final bool modifie;
}

/// Les messages STRUCTURÉS qu'une charge peut porter dans son texte —
/// `STICKER` depuis le 24/10/2026 (même vecteur que le web).
const genresCharge = {'CONTACT', 'LOCATION', 'STICKER'};

class ChargeInvalide implements Exception {
  const ChargeInvalide(this.message);
  final String message;
  @override
  String toString() => 'ChargeInvalide: $message';
}

/// Construit la charge v2 à chiffrer pour le message [id].
///
/// ⚠️ LES CHAMPS ABSENTS NE S'ÉCRIVENT PAS : sans citation ni genre, la charge
/// reste octet pour octet celle d'avant le 06/10/2026, et dans le MÊME ORDRE
/// que le web (`ecrireCharge`, e2ee-media.ts). Un ancien lecteur ignore les
/// deux champs.
String ecrireCharge(
  String id,
  String texte, [
  DescripteurMedia? media,
  String? reponseA,
  String? genre,
  bool modifie = false,
]) =>
    prefixeChargeV2 +
    jsonEncode({
      'v': 2,
      'id': id,
      'texte': texte,
      if (media != null) 'media': media.toJson(),
      if (reponseA != null && reponseA.isNotEmpty) 'reponseA': reponseA,
      if (genre != null) 'genre': genre,
      if (modifie) 'modifie': true,
    });

/// Lit une enveloppe déchiffrée : texte nu (v1) tel quel, charge v2 décodée
/// et VÉRIFIÉE — l'identifiant annoncé doit être celui du message auquel le
/// serveur a rattaché l'enveloppe.
Charge lireCharge(String clair, String? messageId) {
  if (!clair.startsWith(prefixeChargeV2)) return Charge(texte: clair);
  Object? brut;
  try {
    brut = jsonDecode(clair.substring(prefixeChargeV2.length));
  } catch (_) {
    throw const ChargeInvalide('charge v2 illisible');
  }
  if (brut is! Map || brut['v'] != 2 || brut['id'] is! String) {
    throw const ChargeInvalide('charge v2 mal formée');
  }
  if (messageId == null || brut['id'] != messageId) {
    throw const ChargeInvalide(
      'charge rattachée à un autre message que le sien',
    );
  }
  return Charge(
    texte: brut['texte'] is String ? brut['texte'] as String : '',
    media: brut['media'] == null
        ? null
        : DescripteurMedia.depuisJson(brut['media']),
    idAnnonce: brut['id'] as String,
    reponseA: brut['reponseA'] is String && (brut['reponseA'] as String).isNotEmpty
        ? brut['reponseA'] as String
        : null,
    // Un genre inconnu (version future) est ignoré : le texte s'affiche tel quel.
    genre: genresCharge.contains(brut['genre']) ? brut['genre'] as String : null,
    modifie: brut['modifie'] == true,
  );
}

/// Le type de message que le serveur connaît, déduit du VRAI type du fichier.
String typeMessagePour(DescripteurMedia? m) {
  if (m == null) return 'TEXT';
  if (m.mime.startsWith('image/')) return 'IMAGE';
  if (m.mime.startsWith('video/')) return 'VIDEO';
  if (m.mime.startsWith('audio/')) return 'AUDIO';
  return 'FILE';
}

/// Ce que le serveur rendrait pour ce média : un fichier neutre, marqué chiffré.
/// Sert à ranger un message relevé COMPLET, avant que le serveur ait rendu le
/// sien.
Map<String, dynamic> ligneMediaChiffre(DescripteurMedia m) => {
  'id': m.id,
  'url': '/api/media/${m.id}',
  'filename': 'chiffre.bin',
  'mimeType': 'application/octet-stream',
  'sizeBytes': 0,
  'chiffre': true,
};

// ════════════════════════════════════════════════════════════════════════════
// 2. LE FICHIER CHIFFRÉ — format AGB1 (voir le jumeau web pour le détail)
// ════════════════════════════════════════════════════════════════════════════

const tailleBloc = 64 * 1024;
const _tailleTag = 16;

Uint8List _nonce(int index, bool dernier) {
  final n = Uint8List(12);
  ByteData.sublistView(n).setUint32(7, index, Endian.big);
  n[11] = dernier ? 1 : 0;
  return n;
}

Uint8List _gcm(
  bool chiffrer,
  Uint8List cle,
  Uint8List nonce,
  Uint8List entree,
) {
  final c = GCMBlockCipher(AESEngine())
    ..init(
      chiffrer,
      AEADParameters(KeyParameter(cle), 128, nonce, Uint8List(0)),
    );
  return c.process(entree);
}

Uint8List _sha256(Uint8List o) => SHA256Digest().process(o);

/// SHA-256 de [o] — l'empreinte d'un fichier chiffré.
Uint8List empreinteDe(Uint8List o) => _sha256(o);

/// Chiffre le bloc n° [index] d'un fichier AGB1 — [dernier] pour le dernier.
///
/// Le seul morceau du format exposé hors de ce fichier : `e2ee_media_fichier.dart`
/// chiffre de fichier à fichier, bloc par bloc, et doit produire EXACTEMENT les
/// octets de [chiffrerFichier]. Il passe donc par le même nonce et le même GCM,
/// pas par une copie.
Uint8List chiffrerBlocAgb1(Uint8List cle, int index, bool dernier, Uint8List bloc) =>
    _gcm(true, cle, _nonce(index, dernier), bloc);

Uint8List? _b64(String s) {
  try {
    return base64Decode(s);
  } catch (_) {
    return null;
  }
}

class FichierChiffre {
  const FichierChiffre(this.chiffre, this.cle, this.empreinte);
  final Uint8List chiffre;

  /// Clé, base64.
  final String cle;

  /// SHA-256 du chiffré, base64.
  final String empreinte;
}

class FichierInvalide implements Exception {
  const FichierInvalide(this.message);
  final String message;
  @override
  String toString() => 'FichierInvalide: $message';
}

/// Chiffre [clair] avec une clé NEUVE. [cleImposee] n'existe que pour le
/// vecteur de test — une clé réutilisée pour un autre contenu casserait tout.
FichierChiffre chiffrerFichier(Uint8List clair, {Uint8List? cleImposee}) {
  final cle =
      cleImposee ??
      Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
  final nbBlocs = max(1, (clair.length + tailleBloc - 1) ~/ tailleBloc);
  final sortie = BytesBuilder(copy: false);
  for (var i = 0; i < nbBlocs; i++) {
    final fin = min((i + 1) * tailleBloc, clair.length);
    final bloc = Uint8List.sublistView(clair, i * tailleBloc, fin);
    sortie.add(_gcm(true, cle, _nonce(i, i == nbBlocs - 1), bloc));
  }
  final chiffre = sortie.takeBytes();
  return FichierChiffre(
    chiffre,
    base64Encode(cle),
    base64Encode(_sha256(chiffre)),
  );
}

/// Vérifie l'empreinte PUIS déchiffre. Lève [FichierInvalide].
Uint8List dechiffrerFichier(
  Uint8List chiffre, {
  required String cle,
  required String empreinte,
  required int taille,
}) {
  if (base64Encode(_sha256(chiffre)) != empreinte) {
    throw const FichierInvalide(
      'empreinte différente : fichier remplacé ou abîmé',
    );
  }
  final k = _b64(cle);
  if (k == null || k.length != 32) throw const FichierInvalide('clé invalide');
  const tailleBlocChiffre = tailleBloc + _tailleTag;
  final nbBlocs = (chiffre.length + tailleBlocChiffre - 1) ~/ tailleBlocChiffre;
  if (nbBlocs == 0) throw const FichierInvalide('fichier vide');
  final sortie = BytesBuilder(copy: false);
  for (var i = 0; i < nbBlocs; i++) {
    final fin = min((i + 1) * tailleBlocChiffre, chiffre.length);
    final bloc = Uint8List.sublistView(chiffre, i * tailleBlocChiffre, fin);
    if (bloc.length < _tailleTag) throw const FichierInvalide('bloc tronqué');
    try {
      sortie.add(_gcm(false, k, _nonce(i, i == nbBlocs - 1), bloc));
    } catch (_) {
      throw FichierInvalide(
        'bloc $i refusé : clé fausse, ordre changé ou fichier coupé',
      );
    }
  }
  final clair = sortie.takeBytes();
  if (clair.length != taille) {
    throw const FichierInvalide('taille différente de celle annoncée');
  }
  return clair;
}

/// [dechiffrerFichier] DE FICHIER À FICHIER (27/10/2026) : l'empreinte en
/// flux, puis un bloc à la fois. Un gros document reçu ne tient plus en
/// mémoire. SYNCHRONE : à n'appeler que dans un isolat. Lève
/// [FichierInvalide] et efface alors [destination].
void dechiffrerVersFichier({
  required String source,
  required String destination,
  required String cle,
  required String empreinte,
  required int taille,
}) {
  const tailleBlocChiffre = tailleBloc + _tailleTag;
  final entree = File(source).openSync();
  final sortie = File(destination).openSync(mode: FileMode.write);
  var reussi = false;
  try {
    final sha = SHA256Digest();
    while (true) {
      final lu = entree.readSync(1 << 20);
      if (lu.isEmpty) break;
      sha.update(lu, 0, lu.length);
    }
    final calcule = Uint8List(sha.digestSize);
    sha.doFinal(calcule, 0);
    if (base64Encode(calcule) != empreinte) {
      throw const FichierInvalide('empreinte différente : fichier remplacé ou abîmé');
    }
    final k = _b64(cle);
    if (k == null || k.length != 32) throw const FichierInvalide('clé invalide');
    final tailleChiffre = entree.lengthSync();
    final nbBlocs = (tailleChiffre + tailleBlocChiffre - 1) ~/ tailleBlocChiffre;
    if (nbBlocs == 0) throw const FichierInvalide('fichier vide');
    entree.setPositionSync(0);
    var ecrits = 0;
    for (var i = 0; i < nbBlocs; i++) {
      final bloc = entree.readSync(tailleBlocChiffre);
      if (bloc.length < _tailleTag) throw const FichierInvalide('bloc tronqué');
      final Uint8List clair;
      try {
        clair = _gcm(false, k, _nonce(i, i == nbBlocs - 1), bloc);
      } catch (_) {
        throw FichierInvalide(
          'bloc $i refusé : clé fausse, ordre changé ou fichier coupé',
        );
      }
      sortie.writeFromSync(clair);
      ecrits += clair.length;
    }
    if (ecrits != taille) {
      throw const FichierInvalide('taille différente de celle annoncée');
    }
    reussi = true;
  } finally {
    entree.closeSync();
    sortie.closeSync();
    if (!reussi) File(destination).deleteSync();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 4. HORS DU FIL DE L'ÉCRAN
// ════════════════════════════════════════════════════════════════════════════
//
// 🔴 TOUJOURS PASSER PAR CES DEUX FONCTIONS, JAMAIS PAR UN `Isolate.run` ÉCRIT
// SUR PLACE (cours, chapitre 27). Une fermeture envoyée à un isolat emporte
// tout le CONTEXTE de la fonction qui l'a créée : les variables capturées par
// ses voisines, et la chaîne des contextes parents. Dans `EnvoiMediaChiffre`,
// la voisine était le rappel de progression de l'écran, qui tenait l'état du
// chat, qui tenait un `Future` : « object is unsendable » (user, 04/10/2026).
// Ici, le seul contexte est celui des paramètres.

/// [chiffrerFichier] dans un isolat.
Future<FichierChiffre> chiffrerHorsDuFil(Uint8List clair) =>
    Isolate.run(() => chiffrerFichier(clair));

/// [dechiffrerVersFichier] — par le processeur sur Android, dans un isolat
/// sinon. Lève [FichierInvalide].
Future<void> dechiffrerFichierHorsDuFil({
  required String source,
  required String destination,
  required String cle,
  required String empreinte,
  required int taille,
  void Function(double fraction)? onProgression,
}) async {
  final k = _b64(cle);
  if (k != null && k.length == 32) {
    try {
      final fait = await Agb1Natif.dechiffrerFichier(
        source: source,
        destination: destination,
        cle: k,
        empreinte: empreinte,
        taille: taille,
        onProgression: onProgression,
      );
      if (fait) return;
    } on StateError catch (e) {
      throw FichierInvalide(e.message);
    }
  }
  await Isolate.run(
    () => dechiffrerVersFichier(
      source: source,
      destination: destination,
      cle: cle,
      empreinte: empreinte,
      taille: taille,
    ),
  );
}

/// [dechiffrerFichier] — par le processeur sur Android (`Agb1Natif`, mêmes
/// vérifications), dans un isolat sinon. Lève [FichierInvalide].
Future<Uint8List> dechiffrerHorsDuFil(
  Uint8List chiffre, {
  required String cle,
  required String empreinte,
  required int taille,
}) async {
  final k = _b64(cle);
  if (k != null && k.length == 32) {
    try {
      final clair = await Agb1Natif.dechiffrer(chiffre,
          cle: k, empreinte: empreinte, taille: taille);
      if (clair != null) return clair;
    } on StateError catch (e) {
      throw FichierInvalide(e.message);
    }
  }
  return Isolate.run(
    () => dechiffrerFichier(
      chiffre,
      cle: cle,
      empreinte: empreinte,
      taille: taille,
    ),
  );
}
