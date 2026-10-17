import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/api_client.dart';
import '../../../core/downloader.dart';
import '../../../core/media_cache.dart';
import '../../../core/media_helper.dart';
import '../../../services/e2ee/e2ee_media.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/cached_media.dart';
import '../medias_partages.dart';
import '../widgets/bulle_media_chiffre.dart';
import 'media_gallery_viewer.dart';
import 'pdf_viewer_screen.dart';

class _MediaEntry {
  _MediaEntry(this.id, this.url, this.downloadUrl, this.filename, this.isVideo,
      this.durationMs, {this.chiffre});
  final String id, url, downloadUrl, filename;
  final bool isVideo;
  final int? durationMs;

  /// Un média CHIFFRÉ : sa clé et son aperçu, gardés sur ce téléphone. Il se
  /// déchiffre dans sa propre tuile ; la galerie ordinaire lirait le chiffré.
  final DescripteurMedia? chiffre;
}

class _LinkEntry {
  _LinkEntry(this.url, this.at);
  final String url;
  final DateTime at;
}

class _DocEntry {
  _DocEntry(this.downloadUrl, this.displayUrl, this.filename, this.sizeBytes,
      this.type);
  final String downloadUrl, displayUrl, filename;
  final int? sizeBytes;
  final AlanyaMediaType type;
}

/// Contenu partagé d'une conversation — 3 onglets (Média / Liens / Docs), style
/// WhatsApp. Remplace l'ancien lien mort de la fiche contact.
class SharedContentScreen extends StatefulWidget {
  const SharedContentScreen({
    super.key,
    required this.convId,
    required this.title,
  });

  final String convId;
  final String title;

  @override
  State<SharedContentScreen> createState() => _SharedContentScreenState();
}

class _SharedContentScreenState extends State<SharedContentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _loading = true;
  final List<_MediaEntry> _media = [];
  final List<_LinkEntry> _links = [];
  final List<_DocEntry> _docs = [];
  final Map<String, Uint8List> _thumbCache = {};
  String _baseUrl = '';
  String? _token;

  /// Les mêmes médias, prêts pour la galerie (voir `mediasGalerie`).
  List<ConvMediaItem> _galerie = const [];

  static final _urlRe = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final baseUrl = context.read<ApiClient>().baseUrl;
    // Le cache local d'abord : l'écran se remplit sans attendre le réseau.
    try {
      final local = await filPourMediasEnCache(context, widget.convId);
      _remplir(local, baseUrl);
      if (mounted && (_media.isNotEmpty || _docs.isNotEmpty || _links.isNotEmpty)) {
        setState(() => _loading = false);
      }
    } catch (_) {}
    if (!mounted) return;
    try {
      // Toutes les pages, le jeton lu APRÈS, les clés des médias chiffrés :
      // le chargement commun à la fiche contact et à cet écran.
      final fil = await chargerFilPourMedias(context, widget.convId);
      _remplir(fil, baseUrl);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Remplit les trois onglets depuis [fil] — en REMPLAÇANT ce qui y était :
  /// le réseau passe après le cache, sans doublon.
  void _remplir(FilPourMedias fil, String baseUrl) {
    _media.clear();
    _links.clear();
    _docs.clear();
    {
      final msgs = fil.messages;
      final token = fil.token;
      _baseUrl = baseUrl;
      _token = token;
      _galerie = mediasGalerie(msgs,
          baseUrl: baseUrl, token: token, chiffreDe: fil.chiffreDe);

      for (final m in msgs) {
        final content = m.content;
        if (content != null) {
          for (final match in _urlRe.allMatches(content)) {
            _links.add(_LinkEntry(match.group(0)!, m.createdAt));
          }
        }
        // Une vue unique ne figure pas dans les médias partagés : la galerie
        // la montrerait en vignette, sans limite, et le serveur la refuse.
        if (m.vueUnique) continue;
        for (final media in m.media) {
          /*
           * Chiffré : le serveur n'a qu'un fichier illisible. On l'affiche
           * avec la clé gardée localement ; sans elle (enveloppe jamais reçue
           * sur ce téléphone), il n'y a rien à montrer.
           */
          if (media.chiffre) {
            final d = fil.chiffreDe(m);
            if (d != null &&
                (d.mime.startsWith('image/') || d.mime.startsWith('video/'))) {
              _media.add(_MediaEntry(media.id, '', '', d.nom ?? '',
                  d.mime.startsWith('video/'), d.dureeMs,
                  chiffre: d));
            }
            continue;
          }
          final t = MediaHelper.detectType(media.mimeType, media.filename);
          final disp = '$baseUrl${media.url}?token=$token';
          final dl = '$baseUrl${media.url}?download=1&token=$token';
          if (t == AlanyaMediaType.image || t == AlanyaMediaType.video) {
            _media.add(_MediaEntry(media.id, disp, dl, media.filename ?? '',
                t == AlanyaMediaType.video, media.durationMs));
          } else if (t != AlanyaMediaType.audio) {
            _docs.add(_DocEntry(
                dl, disp, media.filename ?? 'fichier', media.sizeBytes, t));
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: themed(context, light: AlanyaColors.terracotta, dark: surfacesOf(context).surface),
        foregroundColor: Colors.white,
        title: Text(widget.title),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Média (${_media.length})'),
            Tab(text: 'Liens (${_links.length})'),
            Tab(text: 'Docs (${_docs.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_mediaTab(), _linksTab(), _docsTab()],
            ),
    );
  }

  // --- MÉDIA ---
  Widget _mediaTab() {
    if (_media.isEmpty) return _empty('Aucun média partagé');
    return GridView.builder(
      padding: const EdgeInsets.all(3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: _media.length,
      itemBuilder: (_, i) {
        final it = _media[i];
        final d = it.chiffre;
        if (d != null) {
          // La tuile déchiffre la sienne ; le toucher ouvre la galerie.
          return TuileMediaChiffre(
              descripteur: d,
              baseUrl: _baseUrl,
              token: _token,
              onOuvrir: () => _openMediaAt(i));
        }
        return GestureDetector(
          onTap: () => _openMediaAt(i),
          child: ColoredBox(
            color: themed(context, light: Colors.black12, dark: surfacesOf(context).surfaceHaute),
            child: it.isVideo
                ? Stack(fit: StackFit.expand, children: [
                    _videoThumb(it),
                    const Center(
                      child: Icon(Icons.play_circle_fill,
                          color: Colors.white, size: 32),
                    ),
                  ])
                : CachedMedia(
                    url: it.url,
                    fit: BoxFit.cover,
                    errorWidget: const Icon(Icons.broken_image,
                        color: Colors.white24),
                  ),
          ),
        );
      },
    );
  }

  /// Ouvre la galerie sur le média touché — en clair ou chiffré, on glisse
  /// de l'un à l'autre.
  void _openMediaAt(int index) {
    final id = _media[index].chiffre?.id ?? _media[index].id;
    final debut = _galerie.indexWhere((e) => e.id == id);
    if (debut < 0) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaGalleryViewer(items: _galerie, initialIndex: debut),
    ));
  }

  Widget _videoThumb(_MediaEntry it) {
    if (_thumbCache.containsKey(it.id)) {
      return Image.memory(_thumbCache[it.id]!, fit: BoxFit.cover);
    }
    _genThumb(it);
    return const ColoredBox(
      color: Color(0xFF1A1A2E),
      child: Icon(Icons.movie, color: Colors.white24, size: 28),
    );
  }

  Future<void> _genThumb(_MediaEntry it) async {
    try {
      final key = 'vthumb_${CachedMedia.cacheKey(it.url)}';
      final cached = await MediaCache.get(key, 'jpg');
      if (cached != null) {
        final bytes = await File(cached).readAsBytes();
        if (mounted) setState(() => _thumbCache[it.id] = bytes);
        return;
      }
      final thumb = await VideoThumbnail.thumbnailData(
          video: it.url,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 300,
          quality: 70);
      if (mounted && thumb != null) {
        await MediaCache.put(key, 'jpg', thumb);
        setState(() => _thumbCache[it.id] = thumb);
      }
    } catch (_) {}
  }

  // --- LIENS ---
  Widget _linksTab() {
    if (_links.isEmpty) return _empty('Aucun lien partagé');
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _links.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final l = _links[i];
        return ListTile(
          tileColor: themed(context, light: Colors.white, dark: surfacesOf(context).surface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: CircleAvatar(
            backgroundColor: themed(context, light: AlanyaColors.sand, dark: surfacesOf(context).surfaceHaute),
            child: Icon(Icons.link, color: positiveOf(context)),
          ),
          title: Text(l.url,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(_fmtDate(l.at),
              style: TextStyle(fontSize: 11, color: mutedOf(context, Colors.black45))),
          onTap: () async {
            final uri = Uri.tryParse(l.url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        );
      },
    );
  }

  // --- DOCS ---
  Widget _docsTab() {
    if (_docs.isEmpty) return _empty('Aucun document partagé');
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final d = _docs[i];
        final color = MediaHelper.colorForType(d.type);
        return ListTile(
          tileColor: themed(context, light: Colors.white, dark: surfacesOf(context).surface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(MediaHelper.iconForType(d.type), color: color),
          ),
          title: Text(d.filename,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: d.sizeBytes != null
              ? Text(MediaHelper.formatSize(d.sizeBytes),
                  style: TextStyle(fontSize: 11, color: mutedOf(context, Colors.black45)))
              : null,
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _openDoc(d),
        );
      },
    );
  }

  Future<void> _openDoc(_DocEntry d) async {
    if (d.type == AlanyaMediaType.pdf) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          pdfUrl: d.displayUrl,
          downloadUrl: d.downloadUrl,
          filename: d.filename,
        ),
      ));
      return;
    }
    final path = await downloadToCache(d.downloadUrl, d.filename);
    if (!mounted) return;
    if (path != null) await openLocalFile(path);
  }

  Widget _empty(String text) => Center(
        child: Text(text, style: TextStyle(color: mutedOf(context, Colors.black45))),
      );

  String _fmtDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
}
