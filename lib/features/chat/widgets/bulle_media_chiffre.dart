import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import '../../../core/authed_api.dart';
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
  });

  final DescripteurMedia descripteur;
  final bool isMe;
  final String baseUrl;
  final String? token;
  final Color couleurDiscrete;
  final VoidCallback? onLongPress;

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

  Widget _document(BuildContext context) {
    final apercu = _apercu;
    final taille = d.taille < 1024 * 1024
        ? '${(d.taille / 1024).ceil()} Ko'
        : '${(d.taille / 1024 / 1024).toStringAsFixed(1)} Mo';
    return InkWell(
      onLongPress: widget.onLongPress,
      onTap: () async {
        final f = _fichier ?? await _charger();
        if (f != null) await OpenFilex.open(f.path);
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            if (apercu != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  apercu,
                  width: 44,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              )
            else
              Icon(
                Icons.description_outlined,
                size: 40,
                color: widget.couleurDiscrete,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.nom ?? tr(context, 'media_file'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [taille, if (d.pages != null) '${d.pages} p.'].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.couleurDiscrete,
                    ),
                  ),
                ],
              ),
            ),
            if (_etat == _Etat.chargement)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
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
  });

  final DescripteurMedia descripteur;
  final String baseUrl;
  final String? token;
  final VoidCallback? onLongPress;

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

/// LE LOT ENTIER, ouvert par « +N » : la grille du fil n'en montre que quatre
/// tuiles, comme le web. Chaque tuile déchiffre la sienne et s'ouvre en plein
/// écran au toucher.
class LotMediasChiffres extends StatelessWidget {
  const LotMediasChiffres({
    super.key,
    required this.descripteurs,
    required this.baseUrl,
    required this.token,
  });

  final List<DescripteurMedia> descripteurs;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${descripteurs.length}'),
    ),
    body: GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: descripteurs.length,
      itemBuilder: (_, i) => TuileMediaChiffre(
        descripteur: descripteurs[i],
        baseUrl: baseUrl,
        token: token,
      ),
    ),
  );
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
