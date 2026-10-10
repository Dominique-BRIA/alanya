import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import '../../../core/authed_api.dart';
import '../../../core/media_helper.dart';
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

  @override
  State<BulleMediaChiffre> createState() => _BulleMediaChiffreState();
}

enum _Etat { attente, chargement, pret, altere, echec }

class _BulleMediaChiffreState extends State<BulleMediaChiffre> {
  _Etat _etat = _Etat.attente;
  File? _fichier;
  AudioPlayer? _audio;
  bool _audioEnCours = false;
  StreamSubscription<PlayerState>? _abonnementAudio;

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
    if (_image) unawaited(_charger());
  }

  @override
  void dispose() {
    _abonnementAudio?.cancel();
    _audio?.dispose();
    super.dispose();
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
                  const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
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

  Widget _bulleVocal(BuildContext context) {
    return InkWell(
      onLongPress: widget.onLongPress,
      onTap: () async {
        final f = _fichier ?? await _charger();
        if (f == null) return;
        if (_audio == null) {
          final p = AudioPlayer();
          _audio = p;
          _abonnementAudio = p.onPlayerStateChanged.listen((s) {
            if (mounted)
              setState(() => _audioEnCours = s == PlayerState.playing);
          });
          await p.play(DeviceFileSource(f.path));
        } else if (_audioEnCours) {
          await _audio!.pause();
        } else {
          await _audio!.resume();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _etat == _Etat.chargement
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : Icon(
                    _audioEnCours
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    size: 34,
                  ),
            const SizedBox(width: 8),
            Text(tr(context, 'vu_vocal')),
            if (d.dureeMs != null) ...[
              const SizedBox(width: 12),
              Text(
                _duree(d.dureeMs!),
                style: TextStyle(fontSize: 12, color: widget.couleurDiscrete),
              ),
            ],
          ],
        ),
      ),
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
        if (f != null) await OpenFilex.open(f.path);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.file_download_outlined,
                      color: widget.couleurDiscrete, size: 22),
              ],
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
  });

  /// Le fichier EN CLAIR, encore en mémoire chez l'expéditeur.
  final Uint8List? octets;
  final String mime;

  /// 0 pendant l'aperçu et le chiffrement, puis le téléversement, puis 1.
  final ValueListenable<double> progression;

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
            child: ValueListenableBuilder<double>(
              valueListenable: progression,
              builder: (context, valeur, _) => valeur >= 1
                  // Les octets sont partis ; restent la ligne et les
                  // enveloppes. On n'écrit pas « terminé », ce serait faux.
                  ? Text(tr(context, 'sending'),
                      style: const TextStyle(color: Colors.white, fontSize: 13))
                  : SizedBox(
                      width: 46,
                      height: 46,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          // Indéterminé pendant le chiffrement : une barre
                          // figée à 0 % ressemblerait à un envoi bloqué.
                          value: valeur <= 0.01 ? null : valeur,
                          strokeWidth: 3,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
                        ),
                        // « 18 % », arrondi VERS LE BAS (demande du user,
                        // 10/10/2026) : `round` affichait 100 alors que le
                        // serveur n'avait pas encore confirmé l'arrivée.
                        if (valeur > 0.01)
                          Text('${(valeur * 100).floor()} %',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                      ]),
                    ),
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
}
