import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/media_cache.dart';
import '../../theme/alanya_theme.dart';

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

  Future<void> _load() async {
    try {
      final path = await MediaCache.getOrFetch(
        mediaId: CachedMedia.cacheKey(widget.url),
        ext: 'dat',
        fetchNetwork: () async {
          final headers = <String, String>{};
          final token = widget.token;
          if (token != null && token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          }
          final res = await http.get(Uri.parse(widget.url), headers: headers);
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

  @override
  Widget build(BuildContext context) {
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
        final res = await http.get(Uri.parse(url), headers: headers);
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        return res.bodyBytes;
      },
    );
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
