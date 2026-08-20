import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/downloader.dart';
import '../../../core/telechargement_suivi.dart';
import '../../../theme/alanya_theme.dart';

/// Visionneuse vidéo plein écran (style WhatsApp).
/// - Lecture/pause au tap
/// - Barre de progression avec seek
/// - Bouton télécharger
/// - Gestion d'erreur : propose le téléchargement si la lecture échoue
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({
    super.key,
    required this.videoUrl,
    required this.downloadUrl,
    required this.filename,
  });

  final String videoUrl;
  final String downloadUrl;
  final String filename;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  bool _showControls = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  String get _cacheName => 'vid_${_idFromUrl(widget.videoUrl)}';

  static String _idFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      if (u.pathSegments.isNotEmpty && u.pathSegments.last.isNotEmpty) {
        return u.pathSegments.last;
      }
    } catch (_) {}
    return url.split('?').first.hashCode.toRadixString(16);
  }

  Future<void> _initPlayer() async {
    // Cache-first : déjà dans le cache app-privé → lecture locale (0 data).
    // Sinon on la télécharge UNE fois dans le cache (dédupliqué) puis on lit en
    // local → jamais re-téléchargée. Fallback streaming si le cache échoue.
    String? localPath;
    try {
      localPath = await getCachedFile(_cacheName);
      localPath ??= await downloadToCache(widget.videoUrl, _cacheName);
    } catch (_) {}
    if (!mounted) return;
    _ctrl = localPath != null
        ? VideoPlayerController.file(File(localPath))
        : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _ctrl!.initialize().then((_) {
      if (mounted && !_hasError) {
        setState(() => _initialized = true);
        _ctrl!.play();
        _ctrl!.setLooping(false);
      }
    }).catchError((e) {
      debugPrint('[VideoViewer] Erreur initialisation: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _initialized = false;
        });
      }
    });
    _ctrl!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    final path = await telechargerEnSuivant(
        widget.downloadUrl, widget.filename,
        idTransfert: "dl-video-${widget.filename}");
    setState(() => _downloading = false);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Vidéo enregistrée dans Alanya/'),
          backgroundColor: AlanyaColors.forest,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => openLocalFile(path),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec du téléchargement'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text(widget.filename, style: const TextStyle(fontSize: 14)),
              actions: [
                IconButton(
                  icon: _downloading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download),
                  onPressed: _downloading ? null : _download,
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: _hasError
            ? Center(child: _errorWidget())
            : _initialized && _ctrl != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: _ctrl!.value.aspectRatio,
                          child: VideoPlayer(_ctrl!),
                        ),
                      ),
                      // Play/pause au centre.
                      if (_showControls) Center(child: _playPauseButton()),
                      // Barre de progression EN BAS (scrim sombre pour lisibilité).
                      if (_showControls)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _bottomBar(),
                        ),
                    ],
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Chargement de la vidéo…',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  /// Widget d'erreur avec bouton de téléchargement de repli.
  Widget _errorWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 56, color: Colors.white54),
        const SizedBox(height: 12),
        const Text(
          'Lecture impossible',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          'Télécharge la vidéo pour la lire avec une autre application.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _downloading ? null : _download,
          icon: const Icon(Icons.download),
          label: const Text('Télécharger'),
        ),
      ],
    );
  }

  Widget _playPauseButton() {
    return IconButton(
      icon: Icon(
        _ctrl!.value.isPlaying
            ? Icons.pause_circle_filled
            : Icons.play_circle_filled,
        color: Colors.white,
        size: 64,
      ),
      onPressed: () {
        setState(() {
          _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
        });
      },
    );
  }

  Widget _bottomBar() {
    final position = _ctrl!.value.position;
    final duration = _ctrl!.value.duration;
    return Container(
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
            Text(_fmtDuration(position),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
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
            Text(_fmtDuration(duration),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
