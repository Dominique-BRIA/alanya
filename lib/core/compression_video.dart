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

// `NiveauQualite` vit dans le module IMAGE, comme sur le web : celui-ci
// l'importe déjà, et l'inverse ferait un import circulaire.
import 'compression_image.dart' show NiveauQualite;

/// Petit côté visé, en pixels — du 720p, comme le web (`VIDEO_BORD_COURT`).
///
/// ⚠️ LE PETIT CÔTÉ, PAS LE GRAND. Une vidéo 16/9 ramenée à 720 de petit côté
/// fait 1280 × 720. La même consigne lue sur le grand côté donnerait
/// 720 × 405 — du 405p, quatre fois moins de pixels, sans que personne l'ait
/// demandé. C'est l'écart n° 2 ci-dessus.
const int videoBordCourtMax = 720;

/// Petit côté visé au niveau haut : du 1080p (web : `VIDEO_BORD_COURT_HAUTE`).
///
/// 🔴 POURQUOI 1080p ET NON « 720p AVEC PLUS DE DÉBIT ». À 720p, les pixels
/// perdus sont perdus : aucun débit ne les ramène. Or la demande vient d'une
/// vidéo de COURS — un tableau, des diapositives. Là, c'est la définition qui
/// rend le texte lisible, pas le débit.
const int videoBordCourtHaute = 1080;

/// Le petit côté visé pour un niveau donné.
int bordCourtVise(NiveauQualite niveau) =>
    niveau == NiveauQualite.haute ? videoBordCourtHaute : videoBordCourtMax;

/// L'ESCALIER DES PALIERS — décision du user, 13/10/2026. Copie du web
/// (`PALIERS_VIDEO`).
///
/// 🐛 « SI LA TAILLE DE LA VIDÉO EST INFÉRIEURE À 720, ON NE COMPRESSE PLUS.
/// Ce n'est pas bon du tout. » On visait 720 et une vidéo déjà en dessous y
/// était déjà : elle repartait intacte.
///
/// 🔴 ON DESCEND TOUJOURS D'UNE MARCHE :
///   · plus grand que 720 → 720   · 361 à 720 → 360
///   · 241 à 360 → 240            · 240 ou moins → on ne touche plus à rien
const List<int> paliersVideo = [720, 360, 240];

/// Le plus petit palier : en dessous, on ne convertit plus.
const int videoPalierPlancher = 240;

/// Le débit de chaque palier, en bits par seconde (web : `DEBIT_PALIER`).
///
/// ⚠️ DES VALEURS EXPLICITES, PAS UNE RÈGLE DE TROIS. Une petite image a besoin
/// de PLUS de bits par pixel qu'une grande pour rester regardable : un 240p
/// calculé au prorata d'un 720p tomberait à 180 kbit/s et serait une bouillie.
const Map<int, int> debitPalier = {720: 1200000, 360: 600000, 240: 300000};

/// Ce que le son ajoute au débit mesuré — marge ADDITIVE, voir le web.
const int margeSon = 250000;

/// Le palier visé pour un petit côté de [court], ou `null` s'il n'y a plus
/// rien à faire. On descend d'une marche, jamais plus, jamais vers le haut.
int? palierVideo(int court) {
  if (court <= videoPalierPlancher) return null;
  for (final p in paliersVideo) {
    if (court > p) return p;
  }
  return null;
}

/// LE SEUIL DE DÉCLENCHEMENT, EN DÉBIT DE FICHIER (web : `SEUIL_DEBIT`).
///
/// 🔴 DEMANDE DU PROFESSEUR, VALIDÉE PAR LE USER LE 16/10/2026 : « tout ce qui
/// est au-dessus de 1,2 Mbit/s, on compresse ». On déclenchait sur la
/// DÉFINITION : une vidéo en 720p à 1 Mbit/s — déjà parfaitement légère —
/// descendait quand même en 360p, parce que l'escalier voulait sa marche.
///
/// Le débit est la bonne variable, et c'est de l'arithmétique : le poids d'un
/// fichier vaut débit × durée. La définition ne fait que plafonner le détail
/// que ce débit peut porter.
///
/// 🔴 CE SEUIL REMPLACE LA GARDE CONTRE LA CASCADE (`dejaUnPalierAlanya`,
/// 13 au 16/10/2026), qui reconnaissait nos propres sorties à leur forme pour
/// qu'une vidéo enregistrée dans la galerie puis renvoyée ne perde pas une
/// marche à chaque tour. Il n'y a plus de forme à reconnaître : AUCUNE de nos
/// sorties ne dépasse le seuil, puisque le seuil EST le débit du palier 720p
/// plus ce que le son ajoute. L'invariant tient par construction.
final int seuilDebit = debitPalier[720]! + margeSon;

/// Ce fichier est-il déjà assez léger pour qu'on n'y touche pas ?
bool dejaAssezLegere(double debit) => debit <= seuilDebit;

/// Débit visé pour du 720p, en bits par seconde (web : `DEBIT_720P`).
///
/// 🔴 C'EST UN DÉBIT DE RÉFÉRENCE, PAS UN PLAFOND FIXE. Il vaut pour du 720p
/// plein ; une image plus petite reçoit sa part, au prorata de sa surface (voir
/// [debitPour]).
///
/// ⚠️ C'EST LE MÊME NOMBRE QUE `debitPalier[720]`, et il doit le rester : le
/// banc `compression_video_test.dart` le vérifie. Dart ne sait pas lire une
/// `const Map` dans un contexte constant, d'où la duplication.
const int debit720p = 1200000;

/// Plancher de débit : en dessous, l'image devient méconnaissable.
const int debitPlancher = 400000;

/* ⚠️ DEUX RÈGLES ONT VÉCU ICI AVANT `seuilDebit` :
 *   · `debitDejaLeger` (jusqu'au 13/10/2026) — un seuil unique qui épargnait
 *     TOUTE vidéo sous 720p, même lourde : le défaut signalé par le user ;
 *   · `dejaUnPalierAlanya` (13 au 16/10/2026) — un seuil par palier, reconnu à
 *     la forme du fichier. Juste, mais il fallait deux règles pour décider.
 * `seuilDebit` fait le travail des deux avec un seul nombre. */

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

/// Le niveau haut donnerait-il vraiment mieux ? (web : `hautePlusFine`)
///
/// 🔴 SERT À NE PAS PROPOSER UN CHOIX QUI NE CHANGE RIEN. On n'agrandit JAMAIS.
///
/// 🐛 LA QUESTION ÉTAIT CELLE D'AVANT L'ESCALIER : « la source dépasse-t-elle
/// 720p ? ». C'était juste quand le niveau normal VISAIT 720p ; depuis
/// l'escalier (13/10/2026) il descend UNE MARCHE EN DESSOUS. Une vidéo filmée
/// en 720p partait donc en 360p et aucun bouton ne permettait de remonter
/// (signalé par le professeur le 16/10/2026). La question juste est
/// COMPARATIVE : le niveau haut donne-t-il une définition plus fine ?
bool hautePlusFine(int bordCourtSource) {
  final normal = palierVideo(bordCourtSource);
  // L'escalier ne fait rien (240p ou moins) : le plafond haut n'y ferait rien
  // non plus, puisqu'on n'agrandit jamais.
  if (normal == null) return false;
  return math.min(bordCourtSource, videoBordCourtHaute) > normal;
}

/// La définition que l'AUTRE niveau donnerait, pour que le bouton l'annonce.
///
/// 🔴 L'ÉTIQUETTE NE PEUT PAS ÊTRE ÉCRITE EN DUR. Elle disait « Envoyer en
/// 1080p », ce qui était faux dès que la source faisait moins : une vidéo
/// filmée en 720p ne rend pas du 1080p.
int definitionAutreNiveauVideo(int court, NiveauQualite niveau) =>
    niveau == NiveauQualite.haute
        ? (palierVideo(court) ?? court)
        : math.min(court, videoBordCourtHaute);

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
  NiveauQualite niveau = NiveauQualite.normal,
}) {
  if (largeur <= 0 || hauteur <= 0) {
    return const ConsigneVideo.saut(RaisonSautVideo.dimensionsInconnues);
  }

  final court = math.min(largeur, hauteur);
  final debitReel =
      dureeMs > 0 ? (tailleOctets * 8) / (dureeMs / 1000) : double.infinity;

  /*
   * ══════ OÙ L'ON DESCEND, ET DE COMBIEN ══════
   *
   * Au niveau NORMAL, l'escalier des paliers : on descend d'une marche et l'on
   * s'arrête à 240. Au niveau HAUT, pas d'escalier — un plafond à 1080, parce
   * que le bouton promet mieux et que le faire descendre serait l'inverse.
   */
  final int vise;
  if (niveau == NiveauQualite.haute) {
    vise = math.min(court, videoBordCourtHaute);
  } else {
    /*
     * ⚠️ LE DÉCLENCHEUR PASSE AVANT L'ESCALIER — voir [seuilDebit]. Un fichier
     * déjà sous le seuil repart intact, quelle que soit sa définition : c'est ce
     * qui évite de descendre une marche pour rien, et c'est aussi ce qui
     * interdit la cascade.
     */
    if (dejaAssezLegere(debitReel)) {
      return const ConsigneVideo.saut(RaisonSautVideo.dejaPetite);
    }
    final palier = palierVideo(court);
    if (palier == null) {
      return const ConsigneVideo.saut(RaisonSautVideo.dejaPetite);
    }
    vise = palier;
  }

  // ⚠️ JAMAIS AGRANDIR : le facteur est plafonné à 1.
  final facteur = math.min(1.0, vise / court);
  final cibleLargeur = _pair(largeur * facteur);
  final cibleHauteur = _pair(hauteur * facteur);
  final debitVise = niveau == NiveauQualite.haute
      ? debitPour(cibleLargeur, cibleHauteur)
      : debitPalier[vise]!;

  /*
   * ⚠️ RIEN À GAGNER : ON S'ABSTIENT PLUTÔT QUE DE TRANSCODER POUR RIEN. Au
   * niveau haut, une vidéo déjà en 1080p peut avoir un débit INFÉRIEUR à celui
   * qu'on viserait : la recompresser l'alourdirait. La règle du gain minimum,
   * plus loin, rendrait bien l'original — mais après avoir fait tourner
   * l'encodeur une minute pour rien, batterie comprise.
   */
  if (debitVise >= debitReel) {
    return const ConsigneVideo.saut(RaisonSautVideo.dejaPetite);
  }

  return ConsigneVideo.transcoder(
    bordCourt: math.min(cibleLargeur, cibleHauteur),
    bordLong: math.max(cibleLargeur, cibleHauteur),
    debit: debitVise,
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
    this.niveauSuperieurPossible = false,
    this.definitionAutreNiveau,
  });

  /// Les octets à envoyer — CEUX D'ORIGINE si rien n'a été fait.
  final Uint8List octets;
  final String nomFichier;
  final String mimeType;
  final bool compresse;
  final int tailleAvant;
  final int tailleApres;
  final RaisonSautVideo? raisonSaut;

  /// Le niveau haut donnerait-il mieux ? Voir [hautePlusFine].
  final bool niveauSuperieurPossible;

  /// La définition que l'autre niveau donnerait, pour l'étiquette du bouton.
  /// `null` tant que les dimensions sont inconnues. Voir
  /// [definitionAutreNiveauVideo].
  final int? definitionAutreNiveau;

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
  NiveauQualite niveau = NiveauQualite.normal,
}) async {
  // Remplis dès que les dimensions sont connues : le bouton ne doit paraître
  // que s'il change quelque chose, et doit dire ce qu'il va produire.
  var hautePossible = false;
  int? definitionAutre;
  ResultatCompressionVideo intact(RaisonSautVideo raison) =>
      ResultatCompressionVideo(
        octets: original,
        nomFichier: nomFichier,
        mimeType: mimeType,
        compresse: false,
        tailleAvant: original.length,
        tailleApres: original.length,
        raisonSaut: raison,
        niveauSuperieurPossible: hautePossible,
        definitionAutreNiveau: definitionAutre,
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

  final courtSource = math.min(largeur, hauteur);
  hautePossible = hautePlusFine(courtSource);
  definitionAutre = definitionAutreNiveauVideo(courtSource, niveau);
  final consigne = consignePour(
    largeur: largeur,
    hauteur: hauteur,
    tailleOctets: original.length,
    dureeMs: dureeMs,
    niveau: niveau,
  );
  if (!consigne.transcode) {
    /*
     * ⚠️ RIEN N'A ÉTÉ FAIT, ET LE NIVEAU HAUT NE FERAIT RIEN NON PLUS : il
     * n'agrandit jamais, et il ne recompresse pas un fichier déjà plus léger
     * que sa propre cible. Le bouton serait une promesse sans suite — c'est la
     * règle du web, à l'identique.
     */
    hautePossible = false;
    return intact(consigne.raison!);
  }

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
    niveauSuperieurPossible: hautePossible,
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
