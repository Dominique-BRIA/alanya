import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import '../../../core/media_helper.dart';
import '../../../theme/alanya_theme.dart';
import 'image_viewer_screen.dart';
import 'video_viewer_screen.dart';
import 'pdf_viewer_screen.dart';

/// Écran galerie style WhatsApp — liste scrollable des médias d'un message.
/// Réutilise les viewers existants : ImageViewerScreen, VideoViewerScreen, PdfViewerScreen.
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
  final Map<String, Uint8List> _thumbCache = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.items.length} média${widget.items.length > 1 ? "s" : ""}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: widget.items.length,
        itemBuilder: (ctx, i) {
          final item = widget.items[i];
          final type = MediaHelper.detectType(item.mimeType, item.fileName);
          final url = '${widget.baseUrl}${item.url}?token=${widget.token}';

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildMediaCard(item, type, url, i),
          );
        },
      ),
    );
  }

  Widget _buildMediaCard(GalleryItem item, AlanyaMediaType type, String url, int index) {
    switch (type) {
      case AlanyaMediaType.image:
        return _buildImageCard(item, url);
      case AlanyaMediaType.video:
        return _buildVideoCard(item, url);
      case AlanyaMediaType.pdf:
        return _buildPdfCard(item, url);
      case AlanyaMediaType.audio:
        return _buildAudioCard(item, url);
      default:
        return _buildDocumentCard(item, url, type);
    }
  }

  /// Image — thumbnail cliquable → ouvre ImageViewerScreen existant
  Widget _buildImageCard(GalleryItem item, String url) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ImageViewerScreen(
            imageUrl: url,
            downloadUrl: url.replaceAll('?token=', '?download=1&token='),
            filename: item.fileName ?? 'image',
          ),
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Image.network(
              url,
              width: double.infinity,
              height: 250,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: double.infinity, height: 250,
                  color: Colors.white10,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AlanyaColors.terracotta,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                width: double.infinity, height: 250,
                color: Colors.white10,
                child: const Icon(Icons.broken_image, color: Colors.white30, size: 48),
              ),
            ),
            // Badge type en haut à gauche
            Positioned(
              top: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.image, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(item.fileName ?? 'Image', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vidéo — thumbnail + play → ouvre VideoViewerScreen existant
  Widget _buildVideoCard(GalleryItem item, String url) {
    final thumbKey = item.url;

    return GestureDetector(
      onTap: () {
        // Utilise le MÊME lecteur que les vidéos envoyées seules
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoViewerScreen(
            videoUrl: url,
            downloadUrl: url.replaceAll('?token=', '?download=1&token='),
            filename: item.fileName ?? 'video',
          ),
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Thumbnail vidéo
            _buildVideoThumbnail(thumbKey, url),
            // Overlay sombre
            Container(
              width: double.infinity, height: 250,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4)],
                ),
              ),
            ),
            // Bouton play central
            const Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white70,
                child: Icon(Icons.play_arrow_rounded, color: Color(0xFF1B1B1B), size: 36),
              ),
            ),
            // Badge durée en bas à gauche
            if (item.durationMs != null && item.durationMs! > 0)
              Positioned(
                bottom: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(MediaHelper.formatDuration(item.durationMs),
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
                ),
              ),
            // Badge nom en haut à gauche
            Positioned(
              top: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.movie, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(item.fileName ?? 'Vidéo', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// PDF — aperçu 1ère page → ouvre PdfViewerScreen existant
  Widget _buildPdfCard(GalleryItem item, String url) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            pdfUrl: url,
            downloadUrl: url.replaceAll('?token=', '?download=1&token='),
            filename: item.fileName ?? 'document.pdf',
          ),
        ));
      },
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.picture_as_pdf, color: Color(0xFFE53935), size: 24),
                Text('PDF', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: const Color(0xFFE53935))),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.fileName ?? 'Document', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  if (item.sizeBytes != null)
                    Text(MediaHelper.formatSize(item.sizeBytes),
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, color: Colors.white30, size: 20),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  /// Audio — info + play
  Widget _buildAudioCard(GalleryItem item, String url) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF00BCD4).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.headphones, color: Color(0xFF00BCD4), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.fileName ?? 'Audio', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                if (item.durationMs != null)
                  Text(MediaHelper.formatDuration(item.durationMs),
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  /// Document (Word, Excel, PPT, etc.)
  Widget _buildDocumentCard(GalleryItem item, String url, AlanyaMediaType type) {
    final color = MediaHelper.colorForType(type);
    final ext = MediaHelper.extension(item.fileName).toUpperCase().replaceAll('.', '');
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(MediaHelper.iconForType(type), color: color, size: 24),
              if (ext.isNotEmpty) Text(ext, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.fileName ?? 'Document', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                if (item.sizeBytes != null)
                  Text(MediaHelper.formatSize(item.sizeBytes),
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.open_in_new, color: Colors.white30, size: 20),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  /// Génère la thumbnail d'une vidéo pour l'affichage dans la galerie.
  Widget _buildVideoThumbnail(String thumbKey, String videoUrl) {
    if (_thumbCache.containsKey(thumbKey)) {
      return Image.memory(_thumbCache[thumbKey]!, width: double.infinity, height: 250, fit: BoxFit.cover);
    }
    _generateThumbnail(thumbKey, videoUrl);
    return Container(
      width: double.infinity, height: 250,
      color: const Color(0xFF1A1A2E),
      child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 48)),
    );
  }

  Future<void> _generateThumbnail(String key, String videoUrl) async {
    try {
      final thumb = await VideoThumbnail.thumbnailData(
        video: videoUrl, imageFormat: ImageFormat.JPEG, maxWidth: 400, quality: 70,
      );
      if (mounted && thumb != null) setState(() => _thumbCache[key] = thumb);
    } catch (_) {}
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
