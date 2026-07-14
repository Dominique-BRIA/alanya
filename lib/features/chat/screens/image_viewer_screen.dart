import 'package:flutter/material.dart';

import '../../../core/downloader.dart';
import '../../../theme/app_theme.dart';

/// Visionneuse plein écran pour une image (style WhatsApp).
/// - Pinch-to-zoom pour zoomer/dézoomer
/// - Bouton télécharger en bas
/// - Tap pour masquer/afficher l'UI
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.downloadUrl,
    required this.filename,
  });

  final String imageUrl;
  final String downloadUrl;
  final String filename;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final _ctrl = TransformationController();
  bool _uiVisible = true;
  bool _downloading = false;

  @override
  void dispose() {
    _ctrl.dispose();
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
          content: Text('Enregistré dans Alanya/ : ${widget.filename}'),
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
      extendBodyBehindAppBar: true,
      appBar: _uiVisible
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text(widget.filename, style: const TextStyle(fontSize: 14)),
              actions: [
                IconButton(
                  icon: _downloading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download),
                  onPressed: _downloading ? null : _download,
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _uiVisible = !_uiVisible),
        child: Center(
          child: InteractiveViewer(
            transformationController: _ctrl,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    value: progress.cumulativeBytesLoaded /
                        (progress.expectedTotalBytes ?? 1),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, size: 64, color: Colors.white38),
                  SizedBox(height: 12),
                  Text('Image indisponible', style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
