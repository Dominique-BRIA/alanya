import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/downloader.dart';
import '../../../theme/app_theme.dart';

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

  void _initPlayer() {
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
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
    final path = await downloadOnly(widget.downloadUrl, widget.filename);
    setState(() => _downloading = false);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Vidéo enregistrée dans Alanya/'),
          backgroundColor: AppColors.forest,
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
        child: Center(
          child: _hasError
              ? _errorWidget()
              : _initialized && _ctrl != null
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _ctrl!.value.aspectRatio,
                          child: VideoPlayer(_ctrl!),
                        ),
                        if (_showControls) _controlsBar(),
                      ],
                    )
                  : const Column(
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

  Widget _controlsBar() {
    final position = _ctrl!.value.position;
    final duration = _ctrl!.value.duration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _ctrl!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: Colors.white,
            size: 56,
          ),
          onPressed: () {
            setState(() {
              _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
            });
          },
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(_fmtDuration(position),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: VideoProgressIndicator(
                  _ctrl!,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: AppColors.terracotta,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              Text(_fmtDuration(duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
