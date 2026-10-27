import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Gestionnaire de cache local pour les médias (images, vidéos, fichiers).
///
/// Vérifie d'abord le stockage local avant de faire une requête réseau.
/// Organisé dans alanya_media_cache/ pour éviter de polluer le dossier de téléchargement.
class MediaCache {
  MediaCache._();

  /// Récupère le chemin local d'un média s'il est en cache, sinon null.
  static Future<String?> get(String mediaId, String ext) async {
    try {
      final dir = await _cacheDir();
      final path = '${dir.path}/$mediaId.$ext';
      final file = File(path);
      if (await file.exists()) return path;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sauvegarde des octets dans le cache et retourne le chemin local.
  static Future<String> put(String mediaId, String ext, List<int> bytes) async {
    try {
      final dir = await _cacheDir();
      final path = '${dir.path}/$mediaId.$ext';
      final file = File(path);
      await file.writeAsBytes(bytes);
      return path;
    } catch (_) {
      rethrow;
    }
  }

  /// Le chemin où [put] rangerait ce média, sans rien écrire (27/10/2026).
  static Future<String> chemin(String mediaId, String ext) async =>
      '${(await _cacheDir()).path}/$mediaId.$ext';

  /// [put] depuis un fichier, copié sans passer en mémoire (26/10/2026).
  static Future<String> putFichier(String mediaId, String ext, String source) async {
    final dir = await _cacheDir();
    final path = '${dir.path}/$mediaId.$ext';
    await File(source).copy(path);
    return path;
  }

  /// Récupère ou télécharge un média : cache d'abord, réseau ensuite.
  /// [fetchNetwork] est appelé seulement si le média n'est pas en cache.
  static Future<String> getOrFetch({
    required String mediaId,
    required String ext,
    required Future<List<int>> Function() fetchNetwork,
  }) async {
    // 1. Vérifie le cache local
    final cached = await get(mediaId, ext);
    if (cached != null) return cached;

    // 2. Télécharge depuis le réseau
    final bytes = await fetchNetwork();
    return put(mediaId, ext, bytes);
  }

  /// Vide entièrement le cache des médias.
  static Future<void> clear() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  static Future<Directory> _cacheDir() async {
    Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/alanya_media_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
