import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../../core/media_helper.dart';
import '../../../theme/alanya_theme.dart';

/// Écran galerie pour afficher tous les médias d'un message.
/// Style WhatsApp : PageView avec swipe, zoom sur images, play sur vidéos.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.items,
    required this.baseUrl,
    this.token,
    this.initialIndex = 0,
  });

  final List<GalleryItem> items;
  final String baseUrl;
  final String? token;
  final int initialIndex;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // TODO: télécharger le média actuel
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (ctx, i) {
          final item = widget.items[i];
          final type = MediaHelper.detectType(item.mimeType, item.fileName);
          final url = '${widget.baseUrl}${item.url}?token=${widget.token}';

          switch (type) {
            case AlanyaMediaType.image:
              return _buildImageViewer(url);
            case AlanyaMediaType.video:
              return _buildVideoViewer(item, url);
            case AlanyaMediaType.audio:
              return _buildAudioPlayer(item, url);
            default:
              return _buildDocumentInfo(item, url);
          }
        },
      ),
    );
  }

  Widget _buildImageViewer(String url) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                color: AlanyaColors.terracotta,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white30, size: 64),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoViewer(GalleryItem item, String url) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_circle_fill, color: Colors.white, size: 80),
          const SizedBox(height: 16),
          Text(
            item.fileName ?? 'Vidéo',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (item.durationMs != null) ...[
            const SizedBox(height: 8),
            Text(
              MediaHelper.formatDuration(item.durationMs),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AlanyaColors.terracotta,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              // TODO: ouvrir le lecteur vidéo intégré
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text("Lire la vidéo"),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayer(GalleryItem item, String url) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.headphones, color: Colors.white, size: 80),
          const SizedBox(height: 16),
          Text(
            item.fileName ?? 'Audio',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (item.durationMs != null) ...[
            const SizedBox(height: 8),
            Text(
              MediaHelper.formatDuration(item.durationMs),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentInfo(GalleryItem item, String url) {
    final type = MediaHelper.detectType(item.mimeType, item.fileName);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(MediaHelper.iconForType(type), color: MediaHelper.colorForType(type), size: 80),
          const SizedBox(height: 16),
          Text(
            item.fileName ?? 'Document',
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (item.sizeBytes != null) ...[
            const SizedBox(height: 8),
            Text(
              MediaHelper.formatSize(item.sizeBytes),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class GalleryItem {
  final String url;
  final String? mimeType;
  final String? fileName;
  final int? sizeBytes;
  final int? durationMs;

  const GalleryItem({
    required this.url,
    this.mimeType,
    this.fileName,
    this.sizeBytes,
    this.durationMs,
  });
}
