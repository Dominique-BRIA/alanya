/// COMPRESSER UNE VIDÉO AVANT DE L'ENVOYER.
///
/// Une vidéo de téléphone sort en 1080p — souvent en 4K — à 20 Mo la minute et
/// plus. Un statut la montre dans un écran de téléphone, pendant 60 secondes au
/// plus. On payait donc, en données mobiles et des DEUX côtés, le transport
/// d'un fichier plusieurs fois plus lourd que ce qui s'affiche. C'est le même
/// raisonnement que pour les photos, et c'est le pendant vidéo de
/// `core/compression_image.dart`.
///
/// ⚠️ CE MODULE PRÉFÈRE TOUJOURS NE RIEN FAIRE, comme son jumeau côté image.
/// Chaque incertitude — pas de chemin de fichier, dimensions inconnues,
/// transcodage refusé, gain absent — rend la vidéo d'origine. Une vidéo
/// envoyée intacte est un non-événement ; une vidéo muette, retournée ou
/// tronquée est un défaut que l'utilisateur découvre chez son correspondant.
///
/// 🔴 LE WEB EST LA RÉFÉRENCE, ET CE FICHIER EN EST LA COPIE (décision du user,
/// 12/10/2026 : « c'est le web qui est déjà bon, c'est le mobile qu'il faut
/// aligner »).
///
/// 🐛 CE QUI N'ÉTAIT PAS ALIGNÉ, ET CE QUE ÇA COÛTAIT. Une vidéo de plus de
/// 30 Mo ressortait à 3,9 Mo sur le web et à 8,9 Mo sur le téléphone — plus du
/// double, pour la même vidéo. Trois écarts, tous corrigés ici :
///
///   1. **LE DÉBIT N'ÉTAIT PAS IMPOSÉ.** On ne demandait que la taille de
///      l'image (`Res1280x720Quality`) et le moteur choisissait le débit tout
///      seul — au double de celui du web. L'API Dart de `video_compress` ne
///      sait pas le transmettre ; on passe donc par `CompresseurVideo.kt`, qui
///      parle au même moteur avec la consigne complète.
///   2. **ON MESURAIT LE GRAND CÔTÉ** (`bordLong <= 720`), là où le web mesure
///      le PETIT. Une vidéo 1280 × 720 — du 720p, donc déjà à l'objectif —
///      était retranscodée, et une vidéo 720 × 720 était épargnée à tort.
///   3. **LE DÉBIT RÉEL DE LA SOURCE ÉTAIT IGNORÉ.** Une vidéo déjà légère
///      était retranscodée ; une vidéo petite mais à très haut débit, épargnée.
///
/// 🔴 LES NOMBRES NE SONT PAS À CHOISIR ICI. Ce sont ceux du web, recopiés de
/// `src/lib/video-compression.ts` : 720 pour le petit côté, 1,6 Mbit/s pour du
/// 720p, 2,5 Mbit/s pour « déjà légère », 10 % de gain minimum. Les changer
/// d'un seul côté ferait repartir l'écart que ce fichier existe pour fermer.
library;

import 'dart:io';
import 'dart:math' as math;

// `Uint8List` vient de `dart:typed_data`, que `services.dart` réexporte.
import 'package:flutter/services.dart';
import 'package:video_compress/video_compress.dart';

/// Petit côté visé, en pixels — du 720p, comme le web (`VIDEO_BORD_COURT`).
///
/// ⚠️ LE PETIT CÔTÉ, PAS LE GRAND. Une vidéo 16/9 ramenée à 720 de petit côté
/// fait 1280 × 720. La même consigne lue sur le grand côté donnerait
/// 720 × 405 — du 405p, quatre fois moins de pixels, sans que personne l'ait
/// demandé. C'est l'écart n° 2 ci-dessus.
const int videoBordCourtMax = 720;

/// Débit visé pour du 720p, en bits par seconde (web : `DEBIT_720P`).
///
/// 🔴 C'EST UN DÉBIT DE RÉFÉRENCE, PAS UN PLAFOND FIXE. Il vaut pour du 720p
/// plein ; une image plus petite reçoit sa part, au prorata de sa surface (voir
/// [debitPour]). Repère WhatsApp : 1,2 à 1,6 Mbit/s.
const int debit720p = 1600000;

/// Plancher de débit : en dessous, l'image devient méconnaissable.
const int debitPlancher = 400000;

/// Au-dessus de ce débit seulement, une vidéo déjà en 720p est retouchée
/// (web : `DEBIT_DEJA_LEGER`).
///
/// 🔴 C'EST LUI QUI EMPÊCHE UNE VIDÉO DE S'ABÎMER À CHAQUE PARTAGE. Une vidéo
/// sortie d'ici tourne autour de 1,8 Mbit/s, son compris : sans cette marge,
/// elle serait retranscodée à chaque transfert, un peu plus pâle chaque fois.
const int debitDejaLeger = 2500000;

/// En dessous, le gain ne vaut pas le risque de perte : on garde l'original.
const double gainMinimumVideo = 0.9;

/// Le canal vers `CompresseurVideo.kt`.
const MethodChannel _canal = MethodChannel('alanya/compression_video');

/// Pourquoi la compression n'a rien fait. Sert au diagnostic, pas à l'affichage.
///
/// 🔴 CE QUI SE VOIT À L'ÉCRAN, C'EST L'ABSENCE DE LIGNE — exactement comme le
/// web (décision du user, 12/10/2026 : « lorsque le mobile ne peut pas
/// compresser, il n'affiche juste pas ce truc-là »). La ligne
/// « 12 Mo → 3,9 Mo · Envoyer l'original » ne paraît que si quelque chose a
/// vraiment été gagné ; rien n'est inventé pour meubler.
enum RaisonSautVideo {
  pasUneVideo,

  /// Le média n'a pas de fichier sur le disque : le transcodage travaille sur
  /// un chemin, pas sur des octets en mémoire.
  sansFichier,

  /// On n'a pas pu lire les dimensions, donc pas su si elle valait le coup.
  dimensionsInconnues,

  /// Déjà à l'objectif : petit côté à 720 ou moins, ET débit raisonnable.
  /// C'est le cas d'une vidéo déjà passée par Alanya, qu'on repartage.
  dejaPetite,

  /// Le transcodage a échoué, ou a été refusé par le module natif.
  transcodageImpossible,

  sansGain,
}

/// La consigne à donner au moteur, ou la raison de ne rien faire.
///
/// 🔴 SÉPARÉE DE TOUT APPEL NATIF, ET C'EST TOUT L'INTÉRÊT. La règle est ce qui
/// doit rester identique au web ; un transcodeur ne se vérifie que sur un
/// téléphone, une règle se vérifie partout — voir
/// `test/compression_video_test.dart`.
class ConsigneVideo {
  const ConsigneVideo.saut(RaisonSautVideo this.raison)
      : bordCourt = 0,
        bordLong = 0,
        debit = 0;

  const ConsigneVideo.transcoder({
    required this.bordCourt,
    required this.bordLong,
    required this.debit,
  }) : raison = null;

  /// `null` quand il faut transcoder.
  final RaisonSautVideo? raison;
  final int bordCourt;
  final int bordLong;
  final int debit;

  bool get transcode => raison == null;
}

/// Le débit d'une image de [largeur] × [hauteur], au prorata du 720p.
///
/// Copie de la ligne du web : une vidéo plus petite que du 720p n'a pas besoin
/// du débit d'un 720p.
int debitPour(int largeur, int hauteur) {
  final part = (debit720p * largeur * hauteur) / (1280 * 720);
  return math.max(debitPlancher, part.round());
}

/// H.264 veut des dimensions paires.
int _pair(num n) => math.max(2, 2 * (n / 2).round());

/// Faut-il transcoder, et avec quelle consigne ? Règle du web, à l'identique.
///
/// [dureeMs] inconnue vaut « débit inconnu » : on ne peut pas conclure qu'elle
/// est déjà légère, donc on transcode — c'est le choix du web, qui prend
/// `Infinity` dans ce cas.
ConsigneVideo consignePour({
  required int largeur,
  required int hauteur,
  required int tailleOctets,
  required int dureeMs,
}) {
  if (largeur <= 0 || hauteur <= 0) {
    return const ConsigneVideo.saut(RaisonSautVideo.dimensionsInconnues);
  }

  final court = math.min(largeur, hauteur);
  final debitReel =
      dureeMs > 0 ? (tailleOctets * 8) / (dureeMs / 1000) : double.infinity;

  /*
   * DÉJÀ À L'OBJECTIF : on n'y touche pas. Les DEUX conditions comptent — une
   * vidéo 720p filmée à 6 Mbit/s mérite encore d'être allégée, et c'est le cas
   * n° 3 que le mobile ratait.
   */
  if (court <= videoBordCourtMax && debitReel <= debitDejaLeger) {
    return const ConsigneVideo.saut(RaisonSautVideo.dejaPetite);
  }

  // ⚠️ JAMAIS AGRANDIR : le facteur est plafonné à 1. Une vidéo 480 × 270 garde
  // ses dimensions et ne voit baisser que son débit.
  final facteur = math.min(1.0, videoBordCourtMax / court);
  final cibleLargeur = _pair(largeur * facteur);
  final cibleHauteur = _pair(hauteur * facteur);

  return ConsigneVideo.transcoder(
    bordCourt: math.min(cibleLargeur, cibleHauteur),
    bordLong: math.max(cibleLargeur, cibleHauteur),
    debit: debitPour(cibleLargeur, cibleHauteur),
  );
}

class ResultatCompressionVideo {
  const ResultatCompressionVideo({
    required this.octets,
    required this.nomFichier,
    required this.mimeType,
    required this.compresse,
    required this.tailleAvant,
    required this.tailleApres,
    this.raisonSaut,
  });

  /// Les octets à envoyer — CEUX D'ORIGINE si rien n'a été fait.
  final Uint8List octets;
  final String nomFichier;
  final String mimeType;
  final bool compresse;
  final int tailleAvant;
  final int tailleApres;
  final RaisonSautVideo? raisonSaut;

  /// Ce que l'envoi a économisé, entre 0 et 1.
  double get gain => tailleAvant <= 0 ? 0 : 1 - (tailleApres / tailleAvant);
}

/// Transcode la vidéo de [chemin] comme le ferait le web, ou rend [original].
///
/// [original] est indispensable : c'est la porte de sortie de chaque refus.
///
/// [onProgression] reçoit l'avancement de 0 à 1. Il n'est appelé QUE si un
/// transcodage a vraiment lieu : annoncer « Compression… » pour une vidéo qu'on
/// ne touchera pas est précisément ce qu'on reprochait au mobile.
Future<ResultatCompressionVideo> compresserVideo(
  Uint8List original, {
  required String? chemin,
  required String nomFichier,
  required String mimeType,
  void Function(double avancement)? onProgression,
}) async {
  ResultatCompressionVideo intact(RaisonSautVideo raison) =>
      ResultatCompressionVideo(
        octets: original,
        nomFichier: nomFichier,
        mimeType: mimeType,
        compresse: false,
        tailleAvant: original.length,
        tailleApres: original.length,
        raisonSaut: raison,
      );

  if (!mimeType.toLowerCase().startsWith("video/")) {
    return intact(RaisonSautVideo.pasUneVideo);
  }
  if (chemin == null || chemin.isEmpty) {
    return intact(RaisonSautVideo.sansFichier);
  }

  /*
   * ⚠️ TEST SUR LES DIMENSIONS ET LE DÉBIT, PAS SUR LE POIDS — même raison que
   * pour les photos : c'est lui qui empêche de transcoder indéfiniment une
   * vidéo déjà passée par ici. Une vidéo reçue puis repartagée perdrait un peu
   * de qualité à chaque saut.
   */
  int largeur = 0;
  int hauteur = 0;
  int dureeMs = 0;
  try {
    final info = await VideoCompress.getMediaInfo(chemin);
    largeur = info.width ?? 0;
    hauteur = info.height ?? 0;
    dureeMs = (info.duration ?? 0).round();
  } catch (_) {
    // Fichier illisible par le module natif : on n'y touche pas.
  }

  final consigne = consignePour(
    largeur: largeur,
    hauteur: hauteur,
    tailleOctets: original.length,
    dureeMs: dureeMs,
  );
  if (!consigne.transcode) return intact(consigne.raison!);

  final produit = await _transcoder(chemin, consigne, onProgression);
  if (produit == null) return intact(RaisonSautVideo.transcodageImpossible);

  final fichier = File(produit);
  Uint8List octets;
  try {
    octets = await fichier.readAsBytes();
  } catch (_) {
    return intact(RaisonSautVideo.transcodageImpossible);
  } finally {
    // Le transcodage laisse son fichier dans le cache de l'application. Une
    // vidéo pèse plusieurs mégaoctets : on ne les garde pas.
    try {
      await fichier.delete();
    } catch (_) {}
  }

  if (octets.isEmpty) return intact(RaisonSautVideo.transcodageImpossible);
  if (octets.length >= original.length * gainMinimumVideo) {
    return intact(RaisonSautVideo.sansGain);
  }

  /*
   * LE NOM ET LE TYPE SUIVENT LES OCTETS, comme pour les photos : le serveur
   * choisit l'extension de stockage d'après le NOM avant de regarder le type.
   * Le module natif rend toujours du MP4, quel que soit le conteneur d'entrée
   * — un `.mov` transcodé qui garderait son nom serait servi plus tard avec le
   * mauvais en-tête.
   */
  return ResultatCompressionVideo(
    octets: octets,
    nomFichier: _enMp4(nomFichier),
    mimeType: "video/mp4",
    compresse: true,
    tailleAvant: original.length,
    tailleApres: octets.length,
  );
}

/// Où envoyer l'avancement du transcodage en cours.
void Function(double)? _avancementEnCours;
bool _canalBranche = false;

/// Appelle `CompresseurVideo.kt` et rend le chemin produit, ou `null`.
///
/// ⚠️ UNE SEULE CONVERSION À LA FOIS, et le côté natif le garantit aussi : les
/// encodeurs matériels sont en nombre limité, et deux conversions simultanées
/// finissent toutes les deux plus tard qu'en file. Les appelants — les deux
/// sélecteurs et les statuts — enchaînent déjà séquentiellement.
Future<String?> _transcoder(
  String chemin,
  ConsigneVideo consigne,
  void Function(double)? onProgression,
) async {
  if (!_canalBranche) {
    _canalBranche = true;
    _canal.setMethodCallHandler((appel) async {
      if (appel.method == 'progression') {
        final v = (appel.arguments as num?)?.toDouble() ?? 0;
        _avancementEnCours?.call(v.clamp(0.0, 1.0));
      }
      return null;
    });
  }
  _avancementEnCours = onProgression;
  try {
    return await _canal.invokeMethod<String>('compresser', {
      'chemin': chemin,
      'bordCourt': consigne.bordCourt,
      'bordLong': consigne.bordLong,
      'debit': consigne.debit,
    });
  } catch (_) {
    // Canal absent (un test, une plateforme sans code natif) ou transcodage
    // refusé : la vidéo part intacte.
    return null;
  } finally {
    _avancementEnCours = null;
  }
}

String _enMp4(String nom) {
  final point = nom.lastIndexOf('.');
  final base = point > 0 ? nom.substring(0, point) : nom;
  return "$base.mp4";
}
