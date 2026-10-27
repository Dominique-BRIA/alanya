import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import '../../../core/authed_api.dart';
import '../../../core/media_helper.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/bulle_vocale.dart';
import '../screens/visionneuse_document_sensible.dart';
import 'infos_protection_pdf.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/e2ee/e2ee_media.dart';
import '../../../services/e2ee/e2ee_media_ouverture.dart';

/// UN MÉDIA CHIFFRÉ DANS UNE BULLE — jumeau du composant web `MediaChiffre`
/// (cours, chapitre 23).
///
/// 🔴 L'APERÇU S'AFFICHE TOUT DE SUITE, SANS RIEN TÉLÉCHARGER : il est arrivé
/// dans l'enveloppe avec la clé. Les dimensions aussi — la bulle prend sa
/// taille d'emblée et le fil ne saute pas quand l'image nette arrive.
///
/// Photo : téléchargée et déchiffrée d'office. Vidéo, vocal, document : sur
/// demande — on ne fait pas télécharger cinquante mégaoctets à qui fait
/// défiler un fil.
///
/// ⚠️ UN FICHIER ALTÉRÉ LE DIT, au lieu d'afficher une image cassée.
class BulleMediaChiffre extends StatefulWidget {
  const BulleMediaChiffre({
    super.key,
    required this.descripteur,
    required this.isMe,
    required this.baseUrl,
    required this.token,
    required this.couleurDiscrete,
    this.onLongPress,
    this.onOuvrir,
    this.convId,
    this.expediteurId,
  });

  final DescripteurMedia descripteur;
  final bool isMe;
  final String baseUrl;
  final String? token;
  final Color couleurDiscrete;
  final VoidCallback? onLongPress;

  /// Ouvre la GALERIE de la conversation sur ce média, pour glisser vers les
  /// autres. Sans lui, le toucher ouvre ce seul média en plein écran.
  final VoidCallback? onOuvrir;

  /// Pour un document SENSIBLE : la conversation et l'Alanya ID de
  /// l'expéditeur, notés dans la trace et dans la copie signée.
  final String? convId;
  final String? expediteurId;

  @override
  State<BulleMediaChiffre> createState() => _BulleMediaChiffreState();
}

enum _Etat { attente, chargement, pret, altere, echec }

class _BulleMediaChiffreState extends State<BulleMediaChiffre> {
  _Etat _etat = _Etat.attente;
  File? _fichier;

  DescripteurMedia get d => widget.descripteur;
  bool get _image => d.mime.startsWith('image/');
  bool get _video => d.mime.startsWith('video/');
  bool get _vocal => d.mime.startsWith('audio/');

  Uint8List? get _apercu {
    final a = d.apercu;
    if (a == null) return null;
    try {
      return base64Decode(a);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    // Une ouverture lancée avant de quitter la conversation continue : la
    // bulle recréée s'y raccroche, pourcentage compris (27/10/2026).
    if (_image || OuvertureMediaChiffre.enCours(d.id)) {
      unawaited(_charger());
    } else {
      unawaited(_dejaLa());
    }
  }

  /// Déjà téléchargé : la bulle le dit, et un toucher l'ouvre sans réseau.
  Future<void> _dejaLa() async {
    final f = await OuvertureMediaChiffre.dejaLa(d);
    if (f == null || !mounted || _fichier != null) return;
    setState(() {
      _fichier = f;
      _etat = _Etat.pret;
    });
  }

  Future<File?> _charger() async {
    if (_fichier != null) return _fichier;
    setState(() => _etat = _Etat.chargement);
    try {
      final f = await OuvertureMediaChiffre.ouvrir(
        d,
        baseUrl: widget.baseUrl,
        token: widget.token,
        jeton: fournisseurJeton(context),
      );
      if (!mounted) return f;
      setState(() {
        _fichier = f;
        _etat = _Etat.pret;
      });
      return f;
    } on FichierInvalide {
      if (mounted) setState(() => _etat = _Etat.altere);
    } catch (_) {
      if (mounted) setState(() => _etat = _Etat.echec);
    }
    return null;
  }

  double get _ratio {
    final l = d.largeur, h = d.hauteur;
    if (l == null || h == null || l == 0 || h == 0) return 4 / 3;
    return (l / h).clamp(0.5, 2.0);
  }

  String _duree(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_etat == _Etat.altere || _etat == _Etat.echec) {
      return InkWell(
        onTap: _etat == _Etat.echec ? _charger : null,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            tr(
              context,
              _etat == _Etat.altere ? 'e2ee_media_altere' : 'e2ee_media_echec',
            ),
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 13,
              color: widget.couleurDiscrete,
            ),
          ),
        ),
      );
    }
    // Une image ou une vidéo SENSIBLE n'entre pas dans la galerie ordinaire
    // (ni signature ni écran protégé) : carte, puis visionneuse (22/10/2026).
    if (d.sensible) return _document(context);
    if (_image || _video) return _visuel(context);
    if (_vocal) return _bulleVocal(context);
    return _document(context);
  }

  Widget _visuel(BuildContext context) {
    final apercu = _apercu;
    return GestureDetector(
      onLongPress: widget.onLongPress,
      onTap: () async {
        if (widget.onOuvrir != null) return widget.onOuvrir!();
        final f = _fichier ?? await _charger();
        if (f == null || !context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _image ? _ImagePleinEcran(f) : _VideoPleinEcran(f),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 250,
          child: AspectRatio(
            aspectRatio: _ratio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (apercu != null)
                  ImageFiltered(
                    // Flouté pour la photo (3 Ko d'aperçu), net pour la vidéo.
                    imageFilter: _image
                        ? ImageFilter.blur(sigmaX: 8, sigmaY: 8)
                        : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: Image.memory(
                      apercu,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  )
                else
                  Container(color: Colors.black12),
                if (_image && _fichier != null)
                  Image.file(_fichier!, fit: BoxFit.cover),
                if (_etat == _Etat.chargement)
                  Center(
                    child: AvancementOuverture(
                      mediaId: d.id,
                      cote: 28,
                      epaisseur: 3,
                      couleur: Colors.white,
                    ),
                  ),
                if (_video && _etat != _Etat.chargement)
                  const Center(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.black54,
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                if (_video && d.dureeMs != null)
                  Positioned(
                    right: 8,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _duree(d.dureeMs!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Un vocal chiffré : la même bulle qu'en clair (`BulleVocale`), forme
  /// d'onde comprise — le fichier est déchiffré pour la lire.
  ///
  /// ⚠️ PRÉPARÉ DÈS L'AFFICHAGE s'il est petit (un vocal ordinaire pèse
  /// quelques dizaines de Ko) : c'est ce qui donne sa vraie forme d'onde. Au-
  /// delà, on attend le premier toucher, comme pour un document.
  Widget _bulleVocal(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final couleur = widget.isMe
        ? Colors.white
        : (sombre ? AlanyaColors.terracottaNuitLight : AlanyaColors.terracotta);
    return BulleVocale(
      identite: d.id,
      isMe: widget.isMe,
      couleur: couleur,
      couleurDiscrete: widget.couleurDiscrete,
      duree: d.dureeMs == null ? null : Duration(milliseconds: d.dureeMs!),
      chargementAuto: d.taille <= 2 * 1024 * 1024,
      onLongPress: widget.onLongPress,
      obtenirSource: () async => (_fichier ?? await _charger())?.path,
    );
  }

  /*
   * DOCUMENT : LE MÊME CADRE QU'UN DOCUMENT EN CLAIR (`DocumentBubble`).
   *
   * 🐛 « TU AS RÉDUIT LE CADRE DES DOCUMENTS » (signalé par le user le
   * 07/10/2026). Dans un fil chiffré, un document n'était qu'une ligne avec
   * une vignette de 44 × 56 — la taille d'un message —, quand le même PDF en
   * clair montre sa première page sur 240 × 180. Les fils étant désormais
   * chiffrés, tous les documents avaient « rétréci ». La première page arrive
   * dans l'enveloppe : on l'affiche en grand, sans rien télécharger.
   *
   * ⚠️ 240 AU PLUS, JAMAIS PLUS QUE LA BULLE : `maxWidth` borne, la bulle
   * étroite d'un petit écran resserre la carte au lieu de la laisser déborder.
   */
  Widget _document(BuildContext context) {
    final apercu = _apercu;
    final taille = d.taille < 1024 * 1024
        ? '${(d.taille / 1024).ceil()} Ko'
        : '${(d.taille / 1024 / 1024).toStringAsFixed(1)} Mo';
    final nom = d.nom ?? tr(context, 'media_file');
    final genre = MediaHelper.detectType(d.mime, nom);
    final couleur = MediaHelper.colorForType(genre);
    final ext = MediaHelper.extension(nom).toUpperCase().replaceAll('.', '');
    return InkWell(
      onLongPress: widget.onLongPress,
      onTap: () async {
        final f = _fichier ?? await _charger();
        if (f == null || !context.mounted) return;
        // Un document SENSIBLE s'ouvre dans la visionneuse interne : signature
        // aux quatre bords, écran protégé ; ce qui en sort est signé
        // (18/10/2026, revu le 22/10/2026).
        if (d.sensible) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VisionneuseDocumentSensible(
              fichier: f,
              descripteur: d,
              convId: widget.convId,
              expediteurId: widget.expediteurId,
            ),
          ));
          return;
        }
        await OpenFilex.open(f.path);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (d.sensible)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 15, color: Color(0xFFE53935)),
                  const SizedBox(width: 4),
                  Text(tr(context, 'sens_titre'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE53935))),
                ]),
              ),
            if (apercu != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  height: 180,
                  child: Image.memory(
                    apercu,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(MediaHelper.iconForType(genre), color: couleur, size: 20),
                      if (ext.isNotEmpty)
                        Text(
                          ext.length > 4 ? ext.substring(0, 4) : ext,
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            color: couleur,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nom,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [taille, if (d.pages != null) '${d.pages} p.'].join(' · '),
                        style: TextStyle(fontSize: 11, color: widget.couleurDiscrete),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_etat == _Etat.chargement)
                  AvancementOuverture(mediaId: d.id, cote: 20, epaisseur: 2)
                else
                  Icon(
                      _etat == _Etat.pret
                          ? Icons.open_in_new
                          : Icons.file_download_outlined,
                      color: widget.couleurDiscrete,
                      size: 22),
              ],
            ),
            // PDF sensible protégé (24/10/2026) : mots de passe en clair chez
            // l'expéditeur, en vue unique chez le destinataire.
            if (d.sensible && d.protection != null)
              InfosProtectionPdf(
                protection: d.protection!,
                mediaId: d.id,
                isMe: widget.isMe,
                couleurDiscrete: widget.couleurDiscrete,
              ),
          ],
        ),
      ),
    );
  }
}

/// La bulle d'un média chiffré dont CET appareil n'a pas la clé — enveloppe
/// jamais reçue ici. Même règle que pour un texte : le dire.
class MediaChiffreIndisponible extends StatelessWidget {
  const MediaChiffreIndisponible({super.key, required this.couleur});
  final Color couleur;

  @override
  Widget build(BuildContext context) => Text(
    tr(context, 'e2ee_media_indisponible'),
    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: couleur),
  );
}

class _ImagePleinEcran extends StatelessWidget {
  const _ImagePleinEcran(this.fichier);
  final File fichier;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: InteractiveViewer(maxScale: 4, child: Image.file(fichier)),
    ),
  );
}

class _VideoPleinEcran extends StatefulWidget {
  const _VideoPleinEcran(this.fichier);
  final File fichier;

  @override
  State<_VideoPleinEcran> createState() => _VideoPleinEcranState();
}

class _VideoPleinEcranState extends State<_VideoPleinEcran> {
  late final VideoPlayerController _c = VideoPlayerController.file(
    widget.fichier,
  );

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() {});
      _c.play();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: _c.value.isInitialized
          ? GestureDetector(
              onTap: () =>
                  setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
              child: AspectRatio(
                aspectRatio: _c.value.aspectRatio,
                child: VideoPlayer(_c),
              ),
            )
          : const CircularProgressIndicator(color: Colors.white),
    ),
  );
}

/// UNE TUILE DE GRILLE pour un média chiffré — photos envoyées à la suite,
/// regroupées à l'affichage (un message par photo, une grille à l'écran).
///
/// 🐛 SANS ELLE, LA GRILLE AFFICHAIT LE FICHIER DU SERVEUR TEL QUEL — c'est-à-
/// dire le CHIFFRÉ : Android refusait de le décoder (« Failed to decode
/// image »), et les tuiles tournaient sans fin (signalé le 03/10/2026). Jumeau
/// de `TuileChiffree` côté web.
class TuileMediaChiffre extends StatefulWidget {
  const TuileMediaChiffre({
    super.key,
    required this.descripteur,
    required this.baseUrl,
    required this.token,
    this.onLongPress,
    this.onOuvrir,
  });

  final DescripteurMedia descripteur;
  final String baseUrl;
  final String? token;
  final VoidCallback? onLongPress;

  /// Ouvre la GALERIE de la conversation sur ce média, pour glisser vers les
  /// autres. Sans lui, le toucher ouvre ce seul média en plein écran.
  final VoidCallback? onOuvrir;

  @override
  State<TuileMediaChiffre> createState() => _TuileMediaChiffreState();
}

class _TuileMediaChiffreState extends State<TuileMediaChiffre> {
  File? _fichier;
  bool _echec = false;
  bool _charge = false;

  DescripteurMedia get d => widget.descripteur;
  bool get _image => d.mime.startsWith('image/');

  @override
  void initState() {
    super.initState();
    if (_image) _charger();
  }

  Future<File?> _charger() async {
    if (_fichier != null) return _fichier;
    // Un nouvel essai efface l'échec du précédent.
    if (mounted) {
      setState(() {
        _charge = true;
        _echec = false;
      });
    }
    try {
      final f = await OuvertureMediaChiffre.ouvrir(d,
          baseUrl: widget.baseUrl,
          token: widget.token,
          jeton: fournisseurJeton(context));
      if (mounted) {
        setState(() {
          _fichier = f;
          _charge = false;
        });
      }
      return f;
    } catch (_) {
      if (mounted) {
        setState(() {
          _echec = true;
          _charge = false;
        });
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? apercu;
    try {
      if (d.apercu != null) apercu = base64Decode(d.apercu!);
    } catch (_) {}
    return GestureDetector(
      onLongPress: widget.onLongPress,
      onTap: () async {
        if (widget.onOuvrir != null) return widget.onOuvrir!();
        final f = _fichier ?? await _charger();
        if (f == null || !context.mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _image ? _ImagePleinEcran(f) : _VideoPleinEcran(f)));
      },
      child: Stack(fit: StackFit.expand, children: [
        if (apercu != null)
          ImageFiltered(
            imageFilter: _image
                ? ImageFilter.blur(sigmaX: 6, sigmaY: 6)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Image.memory(apercu, fit: BoxFit.cover, gaplessPlayback: true),
          )
        else
          Container(color: Colors.black12),
        if (_fichier != null && _image) Image.file(_fichier!, fit: BoxFit.cover),
        if (_charge)
          const Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
          ),
        if (!_image && !_charge)
          const Center(
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black54,
              child: Icon(Icons.play_arrow, color: Colors.white),
            ),
          ),
        if (_echec)
          const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white70)),
      ]),
    );
  }
}

/// Le jeton À JOUR pour télécharger un média chiffré (voir
/// `OuvertureMediaChiffre._telecharger`), ou `null` hors de l'application
/// (tests de widgets), où le jeton passé par l'écran sert de repli.
FournisseurJeton? fournisseurJeton(BuildContext context) {
  try {
    return context.read<AuthedApi>().jeton;
  } catch (_) {
    return null;
  }
}

/// L'ENVOI D'UN MÉDIA CHIFFRÉ EN COURS — même allure que `SendingMediaBubble`.
///
/// 🐛 « ON VOIT JUSTE UN TRAIT QUI DÉFILE EN BAS » (user, 03/10/2026). La
/// bulle d'attente n'était qu'une barre indéterminée de 200 px : ni la photo
/// qu'on envoie, ni l'avancement. Elle montre désormais la vignette locale
/// sous un voile, et un anneau avec le pourcentage du téléversement.
class EnvoiChiffreEnCours extends StatelessWidget {
  const EnvoiChiffreEnCours({
    super.key,
    required this.octets,
    required this.mime,
    required this.progression,
    this.preparation,
  });

  /// Le fichier EN CLAIR, encore en mémoire chez l'expéditeur.
  final Uint8List? octets;
  final String mime;

  /// 0 pendant l'aperçu et le chiffrement, puis le téléversement, puis 1.
  final ValueListenable<double> progression;

  /// L'avancement du CHIFFREMENT, de 0 à 1 (cours, chapitre 47).
  ///
  /// 🐛 SANS LUI, LA BULLE TOURNAIT SANS CHIFFRE pendant toute la préparation
  /// d'une vidéo (user, 12/10/2026 : « ça tourne, ça stresse la personne qui
  /// envoie »). Elle affiche désormais « Préparation 42 % », puis
  /// « Envoi 18 % » : un chiffre à chaque étape.
  final ValueListenable<double>? preparation;

  @override
  Widget build(BuildContext context) {
    final image = mime.startsWith('image/') && octets != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 236,
        height: 160,
        child: Stack(fit: StackFit.expand, children: [
          if (image)
            // Décodée à la taille de la bulle : une photo d'appareil de
            // 12 Mpx décodée en entier coûterait des dizaines de Mo.
            Image.memory(octets!, fit: BoxFit.cover, cacheWidth: 472)
          else
            Container(
              color: const Color(0xFF1A1A2E),
              child: Icon(
                mime.startsWith('video/')
                    ? Icons.movie_outlined
                    : Icons.insert_drive_file_outlined,
                size: 42,
                color: Colors.white38,
              ),
            ),
          // Voile : sans lui, l'anneau blanc disparaît sur une photo claire.
          Container(color: Colors.black.withValues(alpha: 0.35)),
          Center(
            child: ListenableBuilder(
              listenable: Listenable.merge([progression, preparation]),
              builder: (context, _) => _anneau(context),
            ),
          ),
          const Positioned(
            right: 8,
            bottom: 8,
            child: Icon(Icons.lock_outline, size: 16, color: Colors.white70),
          ),
        ]),
      ),
    );
  }

  /// L'anneau, son pourcentage, et l'étape en cours sous lui : « Chiffrement
  /// en cours… » pendant le chiffrement, « Envoi » pendant le téléversement.
  ///
  /// ⚠️ SEUL LE TOUT PREMIER INSTANT RESTE SANS CHIFFRE : l'aperçu, avant le
  /// premier bloc chiffré. Une barre figée à 0 % y ressemblerait à un envoi
  /// bloqué ; l'étape écrite dessous dit qu'on travaille.
  Widget _anneau(BuildContext context) {
    final envoi = progression.value;
    // Les octets sont partis ; restent la ligne et les enveloppes (ou la
    // publication par le serveur). On n'écrit pas « terminé », ce serait faux.
    if (envoi >= 1) {
      return Text(tr(context, 'sending'),
          style: const TextStyle(color: Colors.white, fontSize: 13));
    }
    final enEnvoi = envoi > 0.01;
    final valeur = enEnvoi ? envoi : (preparation?.value ?? 0);
    final connu = valeur > 0.01;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 46,
        height: 46,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: connu ? valeur : null,
            strokeWidth: 3,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
          // « 18 % », arrondi VERS LE BAS (demande du user, 10/10/2026) :
          // `round` affichait 100 avant que ce soit vrai.
          if (connu)
            Text('${(valeur * 100).floor()} %',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 6),
      Text(tr(context, enEnvoi ? 'sending' : 'envoi_preparation'),
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    ]);
  }
}

/// La roue d'une ouverture en cours, avec son POURCENTAGE (27/10/2026) : elle
/// suit `OuvertureMediaChiffre.avancement`, qui vit hors de la bulle. Sans
/// avancement connu (déchiffrement), elle tourne simplement.
class AvancementOuverture extends StatelessWidget {
  const AvancementOuverture({
    super.key,
    required this.mediaId,
    required this.cote,
    required this.epaisseur,
    this.couleur,
  });

  final String mediaId;
  final double cote;
  final double epaisseur;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final suivi = OuvertureMediaChiffre.avancement(mediaId);
    Widget roue(double? v) => Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: cote,
            height: cote,
            child: CircularProgressIndicator(
              value: v == null || v <= 0 ? null : v,
              strokeWidth: epaisseur,
              color: couleur,
            ),
          ),
          if (v != null && v > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${(v * 100).round()} %',
                  style: TextStyle(fontSize: 10, color: couleur)),
            ),
        ]);
    if (suivi == null) return roue(null);
    return ValueListenableBuilder<double?>(
      valueListenable: suivi,
      builder: (_, v, __) => roue(v),
    );
  }
}
