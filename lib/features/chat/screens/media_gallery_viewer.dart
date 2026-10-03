import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/downloader.dart';
import '../../../core/telechargement_suivi.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/cached_media.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/e2ee/e2ee_media.dart';
import '../../../services/e2ee/e2ee_media_ouverture.dart';
import '../widgets/bulle_media_chiffre.dart' show fournisseurJeton;

/// Un média (image ou vidéo) d'une conversation, pour la galerie navigable.
class ConvMediaItem {
  const ConvMediaItem({
    required this.id,
    required this.url,
    required this.downloadUrl,
    required this.filename,
    required this.isVideo,
    this.chiffre,
  });

  final String id;
  final String url; // URL d'affichage (avec ?token=)
  final String downloadUrl;
  final String filename;
  final bool isVideo;

  /// Un média CHIFFRÉ : la page le déchiffre avec ce descripteur, et [url]
  /// reste vide — le fichier du serveur est illisible tel quel.
  ///
  /// 🐛 SANS LUI, LA GALERIE ÉCARTAIT LES MÉDIAS CHIFFRÉS, et toucher l'un
  /// d'eux ouvrait une page qui ne montrait que lui : on ne pouvait plus
  /// glisser d'un média à l'autre (user, 03/10/2026).
  final DescripteurMedia? chiffre;
}

/// Visionneuse plein écran **navigable** (swipe) sur tous les médias
/// image/vidéo d'une conversation — façon WhatsApp. On ouvre au média touché,
/// puis on glisse pour passer aux suivants/précédents.
class MediaGalleryViewer extends StatefulWidget {
  const MediaGalleryViewer({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<ConvMediaItem> items;
  final int initialIndex;

  @override
  State<MediaGalleryViewer> createState() => _MediaGalleryViewerState();
}

class _MediaGalleryViewerState extends State<MediaGalleryViewer> {
  late final PageController _pageCtrl =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _uiVisible = true;
  bool _downloading = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final item = widget.items[_index];
    setState(() => _downloading = true);
    final path = await telechargerEnSuivant(item.downloadUrl, item.filename,
        idTransfert: "dl-galerie-${item.filename}", ouvrirEnsuite: true);
    if (!mounted) return;
    setState(() => _downloading = false);
    showAppSnackBar(path != null
        ? tr(context, 'saved_to_alanya', {'nom': item.filename})
        : tr(context, 'download_failed'));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items.isNotEmpty ? widget.items[_index] : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _uiVisible = !_uiVisible),
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final it = widget.items[i];
                if (it.chiffre != null && !it.isVideo) {
                  return _PageImageChiffree(
                      key: ValueKey(it.id), descripteur: it.chiffre!);
                }
                if (it.isVideo) {
                  return _GalleryVideoPage(
                    key: ValueKey(it.id),
                    item: it,
                    active: i == _index,
                    uiVisible: _uiVisible,
                  );
                }
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: CachedMedia(
                      url: it.url,
                      fit: BoxFit.contain,
                      placeholder: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Barre du haut (retour, compteur, télécharger).
          if (_uiVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Text(
                          item?.filename.isNotEmpty == true
                              ? item!.filename
                              : "${_index + 1} / ${widget.items.length}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      // Un média chiffré ne s'enregistre pas d'ici : le
                      // fichier du serveur serait illisible.
                      if (item?.chiffre == null)
                      IconButton(
                        icon: _downloading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.download, color: Colors.white),
                        onPressed: _downloading ? null : _download,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Page vidéo de la galerie : miniature + play ; lecture inline à la demande,
/// avec barre de progression en bas. Se met en pause quand on quitte la page.
class _GalleryVideoPage extends StatefulWidget {
  const _GalleryVideoPage({
    super.key,
    required this.item,
    required this.active,
    required this.uiVisible,
  });

  final ConvMediaItem item;
  final bool active;
  final bool uiVisible;

  @override
  State<_GalleryVideoPage> createState() => _GalleryVideoPageState();
}

class _GalleryVideoPageState extends State<_GalleryVideoPage> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _starting = false;
  bool _error = false;

  @override
  void didUpdateWidget(_GalleryVideoPage old) {
    super.didUpdateWidget(old);
    // On quitte cette page → pause.
    if (old.active && !widget.active) _ctrl?.pause();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_ready) {
      _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
      setState(() {});
      return;
    }
    if (_starting) return;
    setState(() => _starting = true);
    try {
      String? path;
      final d = widget.item.chiffre;
      if (d != null) {
        path = (await ouvrirMediaChiffre(context, d)).path;
      } else {
        final name = 'vid_${CachedMedia.cacheKey(widget.item.url)}';
        path = await getCachedFile(name);
        path ??= await downloadToCache(widget.item.url, name);
      }
      _ctrl = path != null
          ? VideoPlayerController.file(File(path))
          : VideoPlayerController.networkUrl(Uri.parse(widget.item.url));
      await _ctrl!.initialize();
      if (!mounted) return;
      _ctrl!.addListener(() {
        if (mounted) setState(() {});
      });
      _ctrl!.play();
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Icon(Icons.error_outline, color: Colors.white54, size: 48),
      );
    }
    if (!_ready || _ctrl == null) {
      // Miniature + bouton play (ou spinner pendant l'init).
      final apercu = _apercuChiffre(widget.item.chiffre);
      return Stack(fit: StackFit.expand, children: [
        if (apercu != null)
          Center(child: Image.memory(apercu, fit: BoxFit.contain)),
        Center(
        child: _starting
            ? const CircularProgressIndicator(color: Colors.white)
            : IconButton(
                icon: const Icon(Icons.play_circle_filled,
                    color: Colors.white, size: 72),
                onPressed: _start,
              ),
        ),
      ]);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _ctrl!.value.aspectRatio,
            child: VideoPlayer(_ctrl!),
          ),
        ),
        if (widget.uiVisible)
          Center(
            child: IconButton(
              icon: Icon(
                _ctrl!.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: Colors.white,
                size: 64,
              ),
              onPressed: () => setState(() =>
                  _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play()),
            ),
          ),
        if (widget.uiVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Text(_fmt(_ctrl!.value.position),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VideoProgressIndicator(
                        _ctrl!,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        colors: VideoProgressColors(
                          playedColor: AlanyaColors.terracotta,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(_fmt(_ctrl!.value.duration),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ouvre un média chiffré pour la galerie : clair en cache, ou téléchargé
/// et déchiffré, avec le jeton À JOUR (voir `OuvertureMediaChiffre`).
Future<File> ouvrirMediaChiffre(BuildContext context, DescripteurMedia d) =>
    OuvertureMediaChiffre.ouvrir(
      d,
      baseUrl: context.read<ApiClient>().baseUrl,
      token: null,
      jeton: fournisseurJeton(context),
    );

Uint8List? _apercuChiffre(DescripteurMedia? d) {
  final a = d?.apercu;
  if (a == null) return null;
  try {
    return base64Decode(a);
  } catch (_) {
    return null;
  }
}

/// Une PHOTO CHIFFRÉE dans la galerie : son aperçu flou tout de suite, puis
/// l'image déchiffrée, zoomable comme les autres.
class _PageImageChiffree extends StatefulWidget {
  const _PageImageChiffree({super.key, required this.descripteur});

  final DescripteurMedia descripteur;

  @override
  State<_PageImageChiffree> createState() => _PageImageChiffreeState();
}

class _PageImageChiffreeState extends State<_PageImageChiffree> {
  File? _fichier;
  bool _echec = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _echec = false);
    try {
      final f = await ouvrirMediaChiffre(context, widget.descripteur);
      if (mounted) setState(() => _fichier = f);
    } catch (_) {
      if (mounted) setState(() => _echec = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fichier = _fichier;
    if (fichier != null) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(child: Image.file(fichier, fit: BoxFit.contain)),
      );
    }
    final apercu = _apercuChiffre(widget.descripteur);
    return Stack(fit: StackFit.expand, children: [
      if (apercu != null)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(child: Image.memory(apercu, fit: BoxFit.contain)),
        ),
      Center(
        child: _echec
            ? TextButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: Text(tr(context, 'e2ee_media_echec'),
                    style: const TextStyle(color: Colors.white)),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    ]);
  }
}
