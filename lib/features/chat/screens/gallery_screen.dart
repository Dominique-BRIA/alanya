import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/downloader.dart';
import '../../../core/media_cache.dart';
import '../../../core/media_helper.dart';
import '../../../widgets/media/cached_media.dart';
import 'media_gallery_viewer.dart';
import 'pdf_viewer_screen.dart';

/// Galerie des médias — grille propre style WhatsApp (cellules carrées, SANS
/// nom au-dessus). Les images/vidéos ouvrent la visionneuse navigable (swipe) ;
/// les documents passent la main à l'OS ou au viewer PDF.
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

  String _url(GalleryItem it) => '${widget.baseUrl}${it.url}?token=${widget.token}';
  String _dl(GalleryItem it) =>
      '${widget.baseUrl}${it.url}?download=1&token=${widget.token}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${widget.items.length} média${widget.items.length > 1 ? "s" : ""}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(3),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
        ),
        itemCount: widget.items.length,
        itemBuilder: (ctx, i) {
          final item = widget.items[i];
          final type = MediaHelper.detectType(item.mimeType, item.fileName);
          return _cell(item, type);
        },
      ),
    );
  }

  Widget _cell(GalleryItem item, AlanyaMediaType type) {
    late final Widget content;
    late final VoidCallback onTap;
    switch (type) {
      case AlanyaMediaType.image:
        content = CachedMedia(
          url: _url(item),
          fit: BoxFit.cover,
          errorWidget: _errCell(),
        );
        onTap = () => _openSwipe(item);
        break;
      case AlanyaMediaType.video:
        content = Stack(
          fit: StackFit.expand,
          children: [
            _videoThumb(item),
            const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black26),
            ),
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 34),
            ),
            if ((item.durationMs ?? 0) > 0)
              Positioned(
                right: 4,
                bottom: 4,
                child: _badge(MediaHelper.formatDuration(item.durationMs)),
              ),
          ],
        );
        onTap = () => _openSwipe(item);
        break;
      case AlanyaMediaType.pdf:
        content = _docCell(Icons.picture_as_pdf, const Color(0xFFE53935), 'PDF');
        onTap = () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PdfViewerScreen(
                pdfUrl: _url(item),
                downloadUrl: _dl(item),
                filename: item.fileName ?? 'document.pdf',
              ),
            ));
        break;
      case AlanyaMediaType.audio:
        content = _docCell(Icons.headphones, const Color(0xFF00BCD4), 'AUDIO');
        onTap = () => _openDoc(item);
        break;
      default:
        final ext =
            MediaHelper.extension(item.fileName).toUpperCase().replaceAll('.', '');
        content = _docCell(
          MediaHelper.iconForType(type),
          MediaHelper.colorForType(type),
          ext.isNotEmpty ? ext : 'FICHIER',
        );
        onTap = () => _openDoc(item);
    }
    return GestureDetector(
      onTap: onTap,
      child: ColoredBox(color: Colors.white10, child: content),
    );
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 10)),
      );

  Widget _errCell() => const ColoredBox(
        color: Colors.white10,
        child: Icon(Icons.broken_image, color: Colors.white24, size: 32),
      );

  Widget _docCell(IconData icon, Color color, String label) {
    return ColoredBox(
      color: Colors.white10,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _videoThumb(GalleryItem item) {
    final key = item.url;
    if (_thumbCache.containsKey(key)) {
      return Image.memory(_thumbCache[key]!, fit: BoxFit.cover);
    }
    _generateThumbnail(key, _url(item));
    return const ColoredBox(
      color: Color(0xFF1A1A2E),
      child: Icon(Icons.movie, color: Colors.white24, size: 32),
    );
  }

  Future<void> _generateThumbnail(String key, String videoUrl) async {
    try {
      final diskKey = 'vthumb_${CachedMedia.cacheKey(videoUrl)}';
      final cachedPath = await MediaCache.get(diskKey, 'jpg');
      if (cachedPath != null) {
        final bytes = await File(cachedPath).readAsBytes();
        if (mounted) setState(() => _thumbCache[key] = bytes);
        return;
      }
      final thumb = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 70,
      );
      if (mounted && thumb != null) {
        await MediaCache.put(diskKey, 'jpg', thumb);
        setState(() => _thumbCache[key] = thumb);
      }
    } catch (_) {}
  }

  // Ouvre la visionneuse navigable (swipe) sur les images/vidéos de cette
  // galerie, positionnée sur l'élément touché.
  void _openSwipe(GalleryItem tapped) {
    final media = <ConvMediaItem>[];
    int idx = 0;
    for (final it in widget.items) {
      final t = MediaHelper.detectType(it.mimeType, it.fileName);
      if (t == AlanyaMediaType.image || t == AlanyaMediaType.video) {
        if (identical(it, tapped)) idx = media.length;
        media.add(ConvMediaItem(
          id: it.url,
          url: _url(it),
          downloadUrl: _dl(it),
          filename: it.fileName ?? '',
          isVideo: t == AlanyaMediaType.video,
        ));
      }
    }
    if (media.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaGalleryViewer(items: media, initialIndex: idx),
    ));
  }

  Future<void> _openDoc(GalleryItem item) async {
    final name = item.fileName ?? 'fichier';
    final path = await downloadToCache(_dl(item), name);
    if (!mounted) return;
    if (path != null) {
      await openLocalFile(path);
    }
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
