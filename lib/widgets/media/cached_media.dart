import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/data_saver_service.dart';
import '../../core/media_cache.dart';
import '../../theme/alanya_theme.dart';

/// GET avec retry (réseau faible) : ré-essaie sur erreur réseau ou 5xx, avec un
/// petit backoff. Les erreurs 4xx (auth, introuvable) ne sont pas ré-essayées.
Future<http.Response> httpGetWithRetry(
  Uri uri,
  Map<String, String> headers, {
  int maxRetries = 2,
}) async {
  int attempt = 0;
  while (true) {
    try {
      final res = await http.get(uri, headers: headers);
      if (res.statusCode >= 500 && attempt < maxRetries) {
        attempt++;
        await Future.delayed(Duration(milliseconds: 400 * attempt));
        continue;
      }
      return res;
    } catch (_) {
      if (attempt < maxRetries) {
        attempt++;
        await Future.delayed(Duration(milliseconds: 400 * attempt));
        continue;
      }
      rethrow;
    }
  }
}

/// Affiche une image de `/api/media/{id}` en la mettant en **cache disque
/// persistant** (via [MediaCache]) : un média déjà téléchargé n'est JAMAIS
/// re-téléchargé, même après redémarrage de l'app.
///
/// Remplace `Image.network(...)` / `AuthNetworkImage` pour tous les médias.
/// - Vérifie le disque (clé = id du média extrait de l'URL) avant tout réseau.
/// - Skeleton pendant le premier chargement, fallback en cas d'erreur.
class CachedMedia extends StatefulWidget {
  const CachedMedia({
    super.key,
    required this.url,
    this.token,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  /// URL du média (peut déjà contenir `?token=`). La clé de cache est l'`id`
  /// (dernier segment du chemin), indépendante du token.
  final String url;

  /// Token JWT optionnel : ajouté en en-tête `Authorization` si fourni.
  final String? token;

  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  /// Clé de cache stable pour une URL média (ignore le token en query).
  static String cacheKey(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty) {
        return uri.pathSegments.last;
      }
    } catch (_) {}
    return url.split('?').first.hashCode.toRadixString(16);
  }

  @override
  State<CachedMedia> createState() => _CachedMediaState();
}

class _CachedMediaState extends State<CachedMedia> {
  String? _path;
  bool _error = false;
  bool _needsManual = false; // mode éco : en attente d'un tap pour télécharger

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CachedMedia old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _path = null;
      _error = false;
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    final key = CachedMedia.cacheKey(widget.url);
    // 1. Déjà en cache disque ? → affichage immédiat (gratuit, même en mode éco).
    try {
      final cached = await MediaCache.get(key, 'dat');
      if (cached != null) {
        if (mounted) {
          setState(() {
            _path = cached;
            _needsManual = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    // 2. Mode éco activé et média absent du cache → téléchargement manuel.
    if (!force && DataSaverService.instance.isOn) {
      setState(() => _needsManual = true);
      return;
    }
    // 3. Télécharge (avec retry) puis met en cache.
    setState(() {
      _needsManual = false;
      _error = false;
    });
    try {
      final path = await MediaCache.getOrFetch(
        mediaId: key,
        ext: 'dat',
        fetchNetwork: () async {
          final headers = <String, String>{};
          final token = widget.token;
          if (token != null && token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          }
          final res = await httpGetWithRetry(Uri.parse(widget.url), headers);
          if (res.statusCode != 200) {
            throw Exception('HTTP ${res.statusCode}');
          }
          return res.bodyBytes;
        },
      );
      if (mounted) setState(() => _path = path);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Widget _wrap(Widget child) {
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }

  Widget _skeleton() {
    return widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height ?? 200,
          color: AlanyaColors.sand,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AlanyaColors.terracotta,
            ),
          ),
        );
  }

  Widget _manualPlaceholder() {
    return GestureDetector(
      onTap: () => _load(force: true),
      child: Container(
        width: widget.width,
        height: widget.height ?? 200,
        color: AlanyaColors.sand,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded, color: AlanyaColors.terracotta, size: 30),
            const SizedBox(height: 4),
            Text('Toucher pour télécharger',
                style: TextStyle(fontSize: 11, color: AlanyaColors.grey500)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_needsManual) return _wrap(_manualPlaceholder());
    if (_error) {
      return _wrap(widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height ?? 200,
            color: AlanyaColors.sand,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image, color: AlanyaColors.grey400),
          ));
    }
    final path = _path;
    if (path == null) return _wrap(_skeleton());
    return _wrap(Image.file(
      File(path),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // Si le fichier est corrompu, on retombe sur l'icône d'erreur.
      errorBuilder: (_, __, ___) =>
          widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height ?? 200,
            color: AlanyaColors.sand,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image, color: AlanyaColors.grey400),
          ),
    ));
  }
}

/// Petit helper : charge les octets d'un média en cache disque (utilisé par les
/// widgets qui ont besoin des bytes, ex. avatars).
Future<Uint8List?> loadCachedMediaBytes(String url, String? token) async {
  try {
    final path = await MediaCache.getOrFetch(
      mediaId: CachedMedia.cacheKey(url),
      ext: 'dat',
      fetchNetwork: () async {
        final headers = <String, String>{};
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        final res = await httpGetWithRetry(Uri.parse(url), headers);
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        return res.bodyBytes;
      },
    );
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
