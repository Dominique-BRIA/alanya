import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/data_saver_service.dart';
import '../../core/media_cache.dart';
import '../../theme/alanya_theme.dart';
import 'shimmer_box.dart';

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

  /// Clé de cache stable pour une URL média (ignore le token JWT en query, mais
  /// distingue les paramètres de génération type Dicebear `?seed=...`).
  ///
  /// 🐛 CORRECTION DU BUG DES AVATARS MAINS/DICEBEAR :
  /// Auparavant, pour toute URL du type `https://api.dicebear.com/7.x/icons/svg?seed=...`,
  /// `uri.pathSegments.last` renvoyait `"svg"`. TOUS les avatars Dicebear recevaient donc
  /// la même clé de cache `"svg"`, et le premier téléchargé écrasait les 10 autres !
  static String cacheKey(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegs = uri.pathSegments;
      if (pathSegs.isNotEmpty) {
        final last = pathSegs.last;
        final isGeneric =
            RegExp(r'^(svg|png|jpg|jpeg|gif|webp)$', caseSensitive: false)
                .hasMatch(last);
        if (uri.query.isNotEmpty || isGeneric) {
          // Exclut le token JWT s'il est en query pour ne pas casser le cache au refresh de token
          final queryClean = uri.queryParameters.entries
              .where((e) => e.key.toLowerCase() != 'token')
              .map((e) => '${e.key}=${e.value}')
              .join('&');
          final queryHash = (queryClean.isNotEmpty ? queryClean : url)
              .hashCode
              .toRadixString(16);
          return '${last}_$queryHash';
        }
        if (last.isNotEmpty) {
          return last;
        }
      }
    } catch (_) {}
    return url.hashCode.toRadixString(16);
  }

  @override
  State<CachedMedia> createState() => _CachedMediaState();
}

class _CachedMediaState extends State<CachedMedia> {
  String? _path;
  bool _error = false;
  bool _needsManual = false; // mode éco : en attente d'un tap pour télécharger
  double? _progress; // progression du téléchargement (0..1), null = indéterminé

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
    // 3. Télécharge (streaming + progression + retry) puis met en cache.
    setState(() {
      _needsManual = false;
      _error = false;
    });
    try {
      final path = await MediaCache.getOrFetch(
        mediaId: key,
        ext: 'dat',
        fetchNetwork: _downloadWithProgress,
      );
      if (mounted) {
        setState(() {
          _path = path;
          _progress = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _progress = null;
        });
      }
    }
  }

  /// Télécharge en flux (pour une barre de progression) avec retry réseau.
  Future<List<int>> _downloadWithProgress() async {
    final headers = <String, String>{};
    final token = widget.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    int attempt = 0;
    while (true) {
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(widget.url))
          ..headers.addAll(headers);
        final resp = await client.send(req);
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        final total = resp.contentLength ?? 0;
        final bytes = <int>[];
        int received = 0;
        await for (final chunk in resp.stream) {
          bytes.addAll(chunk);
          received += chunk.length;
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        }
        return bytes;
      } catch (_) {
        if (attempt < 2) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 400 * attempt));
          continue;
        }
        rethrow;
      } finally {
        client.close();
      }
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
        ShimmerBox(
          width: widget.width,
          height: widget.height,
          progress: _progress,
        );
  }

  Widget _errorBox() {
    return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height ?? 200,
          color: AlanyaColors.sand,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image, color: AlanyaColors.grey400),
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
    Widget child;
    if (_needsManual) {
      child = KeyedSubtree(
        key: const ValueKey('manual'),
        child: _manualPlaceholder(),
      );
    } else if (_error) {
      child = KeyedSubtree(key: const ValueKey('error'), child: _errorBox());
    } else if (_path == null) {
      child = KeyedSubtree(key: const ValueKey('skeleton'), child: _skeleton());
    } else {
      child = Image.file(
        File(_path!),
        key: ValueKey('img_${_path!}'),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        // Si le fichier est corrompu, on retombe sur l'icône d'erreur.
        errorBuilder: (_, __, ___) => _errorBox(),
      );
    }
    // Fondu doux entre skeleton → image (transition fluide, façon WhatsApp).
    return _wrap(AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
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
