import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/e2ee/e2ee_media.dart' show ProtectionPdf;
import 'alanya_id_formatter.dart';
import 'audio_metadonnees.dart';
import 'mp4_metadonnees.dart';
import 'protection_pdf_copie.dart';

/// Ce qu'on fait sortir d'Alanya : le geste noté par le serveur.
enum GesteSortie {
  telechargement('TELECHARGEMENT'),
  partage('PARTAGE'),
  transfert('TRANSFERT');

  const GesteSortie(this.code);

  /// La valeur attendue par `POST /api/documents-sensibles/consultations`.
  final String code;
}

/// LA SIGNATURE D'UNE COPIE QUI SORT (22/10/2026).
///
/// Demande du user : un document sensible se télécharge et se partage
/// désormais librement, mais la copie qui sort porte de quoi remonter à qui
/// l'a fait sortir :
///
/// * aux QUATRE BORDS (PDF, images) : [texteBords] ;
/// * dans les MÉTADONNÉES (PDF, images, vidéos) : [metadonnees] — application,
///   Alanya ID, appareil, date, geste, expéditeur et CODE DE TRACE.
///
/// Le code est tiré ici, au hasard, et envoyé au serveur avec le geste : un
/// fichier retrouvé ailleurs renvoie, par son code, à la ligne
/// `document_consultation` de celui qui l'a fait sortir — même si l'on a
/// effacé le nom écrit dans le fichier.
///
/// Le texte des bords ne contient AUCUN MOT d'une langue : seulement des noms,
/// des chiffres et le code. Il reste lisible dans un PDF quelle que soit la
/// langue de l'application (les polices d'un PDF ne couvrent pas toutes les
/// écritures).
class SignatureSortie {
  SignatureSortie({
    required this.geste,
    required String alanyaId,
    required this.appareil,
    required this.quand,
    required this.code,
    String? expediteurId,
    this.mediaId,
  }) : alanyaId = formatAlanyaId(alanyaId),
       expediteurId = (expediteurId == null || expediteurId.trim().isEmpty)
           ? null
           : formatAlanyaId(expediteurId);

  /// Une signature neuve, avec un code tiré au hasard.
  factory SignatureSortie.nouvelle({
    required GesteSortie geste,
    required String alanyaId,
    required String appareil,
    String? expediteurId,
    String? mediaId,
  }) => SignatureSortie(
    geste: geste,
    alanyaId: alanyaId,
    appareil: appareil,
    quand: DateTime.now(),
    code: nouveauCode(),
    expediteurId: expediteurId,
    mediaId: mediaId,
  );

  static const application = 'Alanya Work';

  final GesteSortie geste;

  /// L'Alanya ID de qui fait sortir la copie, formaté (« 67 64 15 99 »).
  final String alanyaId;

  /// Marque et modèle (« samsung SM-A515F »).
  final String appareil;
  final DateTime quand;

  /// 32 caractères hexadécimaux minuscules.
  final String code;

  /// L'Alanya ID de qui a envoyé le document, s'il est connu.
  final String? expediteurId;
  final String? mediaId;

  /// 128 bits tirés par le générateur sûr du système.
  static String nouveauCode([Random? hasard]) {
    final r = hasard ?? Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// « 3F9A 0C1E 5B7D … » : le code tel qu'on le recopie depuis une photo.
  String get codeLisible {
    final m = code.toUpperCase();
    return [
      for (var i = 0; i < m.length; i += 4)
        m.substring(i, min(i + 4, m.length)),
    ].join(' ');
  }

  static String _deux(int n) => n.toString().padLeft(2, '0');

  String get dateLisible =>
      '${_deux(quand.day)}/${_deux(quand.month)}/${quand.year} '
      '${_deux(quand.hour)}:${_deux(quand.minute)}';

  /// ISO 8601 avec le décalage horaire local (« 2026-10-22T21:40:00+01:00 »).
  String get dateIso {
    final d = quand.timeZoneOffset;
    final signe = d.isNegative ? '-' : '+';
    final a = d.abs();
    return '${quand.year.toString().padLeft(4, '0')}-${_deux(quand.month)}-'
        '${_deux(quand.day)}T${_deux(quand.hour)}:${_deux(quand.minute)}:'
        '${_deux(quand.second)}$signe${_deux(a.inHours)}:${_deux(a.inMinutes % 60)}';
  }

  /// Le numéro seul, chiffres sans espaces ni « AlanyaID : » : ce qu'écrit
  /// une copie PROTÉGÉE en haut à droite (24/10/2026, demande du user).
  String get numeroSeul => alanyaId.replaceAll(RegExp(r'\D'), '');

  /// L'Alanya ID tel que l'écrit le filigrane : « AW 3333 3333 ».
  String get alanyaIdAw {
    final d = numeroSeul;
    return d.length == 8 ? 'AW ${d.substring(0, 4)} ${d.substring(4)}' : 'AW $d';
  }

  /// PHOTOS ET VIDÉOS : UN CHAMP PAR BORD (25/10/2026, recommandation retenue
  /// par le patron) — haut, bas, gauche, droite, séparés par « \n » :
  /// l'application et l'Alanya ID, la date, l'appareil, l'empreinte. Écrits
  /// en blanc cerné de noir, 16 px au moins (`SignatureDocument.kt`).
  String get bordsVisuels => [
    '$application · $alanyaIdAw',
    dateLisible,
    appareil,
    codeLisible,
  ].join('\n');

  /// PDF : l'EMPREINTE NUMÉRIQUE à la place de l'Alanya ID (25/10/2026,
  /// demande du patron). L'Alanya ID reste dans les métadonnées.
  String get texteBordsPdf => [
    application,
    codeLisible,
    appareil,
    dateLisible,
  ].join(' · ');

  /// La chaîne complète (commentaire d'une vidéo, ancien filigrane).
  String get texteBords => [
    application,
    'Alanya $alanyaId',
    appareil,
    dateLisible,
    codeLisible,
  ].join(' · ');

  /// Les métadonnées, sous des noms courts et lisibles (24/10/2026, demande
  /// du user) : clés du dictionnaire Info d'un PDF, commentaire EXIF d'une
  /// image, éléments libres d'une vidéo. Les mêmes que le web.
  Map<String, String> get metadonnees => {
    CleMeta.application: application,
    CleMeta.alanyaId: alanyaId,
    CleMeta.appareil: appareil,
    CleMeta.dateCreation: dateIso,
    CleMeta.empreinte: code,
    CleMeta.geste: geste.code,
    if (expediteurId != null) CleMeta.expediteur: expediteurId!,
    if (mediaId != null) CleMeta.document: mediaId!,
  };

  /// Les mêmes informations pour une vidéo (`moov/udta/meta/ilst`).
  /// 🐛 LES MÉTADONNÉES D'UNE VIDÉO SEMBLAIENT INCOMPLÈTES (user, 25/10/2026) :
  /// les huit champs n'étaient que dans des éléments libres (`----`), que
  /// l'Explorateur de Windows n'affiche pas. Ils vont aussi, en toutes
  /// lettres, dans le COMMENTAIRE (`©cmt`) — comme le commentaire EXIF d'une
  /// image — et l'onglet « Détails » les montre ; titre, description et
  /// copyright suivent.
  ElementsMp4 get elementsMp4 => ElementsMp4(
    standard: {
      '©nam': texteBords,
      'desc': texteBords,
      '©too': application,
      '©ART': 'Alanya $alanyaId',
      '©cmt': [for (final e in metadonnees.entries) '${e.key}=${e.value}'].join('; '),
      '©day': dateIso,
      'cprt': application,
    },
    libres: metadonnees,
  );
}

/// Les noms des champs de métadonnées. Le code natif (`SignatureDocument.kt`)
/// et le web (`signature-document.ts`) lisent et écrivent les mêmes.
class CleMeta {
  CleMeta._();

  static const application = 'Application';
  static const alanyaId = 'Alanya ID';
  static const appareil = 'Appareil';
  static const dateCreation = 'Date Creation';

  /// Le code de trace, noté aussi par le serveur avec le geste.
  static const empreinte = 'Empreinte numerique';
  static const geste = 'Geste';
  static const expediteur = 'Expediteur';
  static const document = 'Document';
}

/// Ce que la signature sait faire d'un fichier.
enum NatureSignature {
  /// Texte aux quatre bords de chaque page, et métadonnées.
  pdf,

  /// Texte aux quatre bords, et EXIF.
  image,

  /// Texte aux quatre bords (vidéo réencodée, Android), et métadonnées ;
  /// à défaut, métadonnées seules.
  video,

  /// L'empreinte SEULE dans les métadonnées (MP3, WAV, M4A) — 25/10/2026.
  audio,

  /// Rien : la copie sort telle quelle (le serveur note quand même le geste).
  aucune,
}

String _extension(String nom) {
  final point = nom.lastIndexOf('.');
  return point < 0 ? '' : nom.substring(point + 1).toLowerCase();
}

const _imagesSignables = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp'};
const _audios = {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'opus', 'flac', 'amr', '3ga', 'weba'};

NatureSignature natureSignature(String mime, String nom) {
  final m = mime.toLowerCase();
  final ext = _extension(nom);
  if (m == 'application/pdf' || ext == 'pdf') return NatureSignature.pdf;
  // Un GIF animé perdrait son animation, un SVG n'est pas une image en
  // points : ils sortent tels quels.
  if (_imagesSignables.contains(ext) ||
      (m.startsWith('image/') && m != 'image/gif' && !m.contains('svg'))) {
    return NatureSignature.image;
  }
  // L'audio AVANT la vidéo : un M4A est un MP4, il ne doit pas être réencodé.
  if (m.startsWith('audio/') || _audios.contains(ext)) return NatureSignature.audio;
  // Toute vidéo peut recevoir l'incrustation (Android la réencode en MP4) ;
  // à défaut, seuls MP4, MOV et 3GP reçoivent les métadonnées.
  if (m.startsWith('video/') || Mp4Metadonnees.prisEnCharge(m, nom)) {
    return NatureSignature.video;
  }
  return NatureSignature.aucune;
}

/// La copie prête à sortir.
class CopieSignee {
  const CopieSignee({
    required this.fichier,
    required this.nom,
    required this.mime,
    required this.signee,
  });

  final File fichier;

  /// Le nom à donner (une image HEIC ou BMP devient un JPEG).
  final String nom;
  final String mime;

  /// Faux : le format n'est pas pris en charge, ou la signature a échoué —
  /// la copie sort telle quelle.
  final bool signee;
}

/// Fabrique la copie signée d'un document sensible.
class SignatureDocument {
  SignatureDocument._();

  static const _canal = MethodChannel('alanya/signature');

  /// Signe une copie de [source] (le clair déchiffré) dans le cache.
  ///
  /// Ne lève jamais : un échec rend la copie telle quelle, avec
  /// `signee: false` — le geste a été demandé, il n'est pas refusé.
  /// [cache] : le dossier de travail (par défaut, le cache de l'application).
  ///
  /// 🔴 SAUF POUR UN PDF PROTÉGÉ ([protection], 24/10/2026) : là, un échec
  /// LÈVE [ProtectionImpossible]. Rendre la copie telle quelle ferait sortir
  /// sans mot de passe ni restriction un document que l'expéditeur a voulu
  /// protéger — le téléchargement échoue plutôt.
  static Future<CopieSignee> signer({
    required File source,
    required String nom,
    required String mime,
    required SignatureSortie signature,
    Directory? cache,
    ProtectionPdf? protection,
  }) async {
    final base = cache ?? await getTemporaryDirectory();
    // Un dossier par code : la copie garde son nom d'origine.
    final dossier = Directory('${base.path}/sorties/${signature.code}');
    await dossier.create(recursive: true);
    final cible = '${dossier.path}/$nom';
    if (protection != null &&
        natureSignature(mime, nom) == NatureSignature.pdf) {
      return _signerProtege(source, nom, mime, cible, signature, protection);
    }
    try {
      switch (natureSignature(mime, nom)) {
        case NatureSignature.pdf:
        case NatureSignature.image:
          final pdf = natureSignature(mime, nom) == NatureSignature.pdf;
          final r = await _canal.invokeMapMethod<String, Object?>('signer', {
            'entree': source.path,
            'sortie': cible,
            'mime': mime,
            'bords': pdf ? signature.texteBordsPdf : signature.bordsVisuels,
            'meta': signature.metadonnees,
          });
          final chemin = r?['chemin'] as String?;
          if (chemin == null) throw StateError('Signature sans fichier');
          final fichier = File(chemin);
          return CopieSignee(
            fichier: fichier,
            nom: fichier.uri.pathSegments.last,
            mime: (r?['mime'] as String?) ?? mime,
            signee: true,
          );
        case NatureSignature.video:
          final incrustee = await _incruster(source, nom, dossier, signature);
          if (incrustee != null) return incrustee;
          // Pas d'incrustation : la copie aux seules métadonnées, si le
          // conteneur le permet.
          if (!Mp4Metadonnees.prisEnCharge(mime, nom)) break;
          await Mp4Metadonnees.ecrire(
            source,
            File(cible),
            signature.elementsMp4,
          );
          return CopieSignee(
            fichier: File(cible),
            nom: nom,
            mime: mime,
            signee: true,
          );
        case NatureSignature.audio:
          final ok = await _empreinteAudio(source, File(cible), signature.code);
          if (!ok) break;
          return CopieSignee(fichier: File(cible), nom: nom, mime: mime, signee: true);
        case NatureSignature.aucune:
          break;
      }
    } catch (e) {
      debugPrint('[Alanya] Signature impossible ($nom) : $e');
    }
    final copie = await source.copy(cible);
    return CopieSignee(fichier: copie, nom: nom, mime: mime, signee: false);
  }

  /// La copie PROTÉGÉE d'un PDF (Syncfusion, `protection_pdf_copie.dart`).
  ///
  /// * Avec mot de passe : le numéro seul en haut à droite, plus aucun texte
  ///   aux quatre bords (demande du user), les métadonnées, le chiffrement.
  /// * Sans mot de passe (impression interdite) : la signature habituelle aux
  ///   quatre bords par le natif, puis la seule restriction par-dessus.
  static Future<CopieSignee> _signerProtege(
    File source,
    String nom,
    String mime,
    String cible,
    SignatureSortie signature,
    ProtectionPdf protection,
  ) async {
    try {
      final CopiePdfProtegee travail;
      if (protection.avecMotDePasse) {
        travail = CopiePdfProtegee(
          octets: await source.readAsBytes(),
          protection: protection,
          // L'empreinte, et non plus l'Alanya ID (25/10/2026, patron).
          coin: signature.codeLisible,
          meta: signature.metadonnees,
        );
      } else {
        final r = await _canal.invokeMapMethod<String, Object?>('signer', {
          'entree': source.path,
          'sortie': cible,
          'mime': mime,
          'bords': signature.texteBordsPdf,
          'meta': signature.metadonnees,
        });
        final chemin = r?['chemin'] as String?;
        if (chemin == null) throw StateError('Signature sans fichier');
        travail = CopiePdfProtegee(
          octets: await File(chemin).readAsBytes(),
          protection: protection,
        );
      }
      final octets = await compute(protegerPdf, travail);
      final fichier = await File(cible).writeAsBytes(octets, flush: true);
      return CopieSignee(
        fichier: fichier,
        nom: nom,
        mime: 'application/pdf',
        signee: true,
      );
    } catch (e) {
      debugPrint('[Alanya] PDF non protégé ($nom) : $e');
      final reste = File(cible);
      if (await reste.exists()) await reste.delete();
      throw ProtectionImpossible(e);
    }
  }

  /// L'empreinte SEULE dans un fichier audio (`audio_metadonnees.dart`).
  /// Rend faux si le format n'est pas pris en charge.
  static Future<bool> _empreinteAudio(File source, File cible, String code) async {
    final debut = await source.openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
    switch (formatAudio(Uint8List.fromList(debut))) {
      case FormatAudio.mp4:
        await Mp4Metadonnees.ecrire(
          source,
          cible,
          ElementsMp4(standard: const {}, libres: {CleMeta.empreinte: code}),
        );
        return true;
      case FormatAudio.mp3:
        await cible.writeAsBytes(avecEmpreinteMp3(await source.readAsBytes(), code), flush: true);
        return true;
      case FormatAudio.wav:
        await cible.writeAsBytes(avecEmpreinteWav(await source.readAsBytes(), code), flush: true);
        return true;
      case null:
        return false;
    }
  }

  /// La signature incrustée aux quatre bords d'une vidéo (Android seulement,
  /// `SignatureVideo.kt`), puis les métadonnées écrites sur le MP4 produit.
  ///
  /// La vidéo est réencodée en MP4 (H.264 / AAC) : la copie prend
  /// l'extension `.mp4`. Rend `null` si l'incrustation est impossible.
  static Future<CopieSignee?> _incruster(
    File source,
    String nom,
    Directory dossier,
    SignatureSortie signature,
  ) async {
    if (!Platform.isAndroid) return null;
    final point = nom.lastIndexOf('.');
    final racine = point > 0 ? nom.substring(0, point) : nom;
    final nomMp4 = '$racine.mp4';
    final brute = File('${dossier.path}/${racine}_incrustee.mp4');
    try {
      final r = await _canal.invokeMapMethod<String, Object?>('signerVideo', {
        'entree': source.path,
        'sortie': brute.path,
        'bords': signature.bordsVisuels,
      });
      if (r?['chemin'] == null || !await brute.exists()) return null;
    } catch (e) {
      debugPrint('[Alanya] Vidéo non incrustée ($nom) : $e');
      if (await brute.exists()) await brute.delete();
      return null;
    }
    final cible = File('${dossier.path}/$nomMp4');
    try {
      await Mp4Metadonnees.ecrire(brute, cible, signature.elementsMp4);
      await brute.delete();
    } catch (e) {
      // Les bords sont là, c'est l'essentiel : la vidéo sort sans métadonnées
      // plutôt que de perdre l'incrustation.
      debugPrint('[Alanya] Métadonnées MP4 non écrites ($nom) : $e');
      if (await cible.exists()) await cible.delete();
      await brute.rename(cible.path);
    }
    return CopieSignee(
      fichier: cible,
      nom: nomMp4,
      mime: 'video/mp4',
      signee: true,
    );
  }
}

/// La copie protégée d'un PDF n'a pas pu être faite : rien ne sort.
class ProtectionImpossible implements Exception {
  const ProtectionImpossible(this.cause);
  final Object cause;

  @override
  String toString() => 'ProtectionImpossible($cause)';
}
