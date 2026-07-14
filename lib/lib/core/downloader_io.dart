import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Téléchargement de médias depuis Alanya vers le stockage **public** du
/// téléphone (visible dans le gestionnaire de fichiers et la galerie).
///
/// Stratégie :
///  - **Android 10+ (API 29+)** : utilise MediaStore API via [media_store_plus].
///    Les fichiers vont dans les dossiers publics standards :
///      * Images → /Pictures/Alanya/
///      * Vidéos → /Movies/Alanya/
///      * Audio  → /Music/Alanya/
///      * Autres → /Download/Alanya/
///    Aucune permission "spéciale" nécessaire, marche même sur Play Store.
///  - **Android < 10** : accès direct à /storage/emulated/0/Alanya/ via
///    WRITE_EXTERNAL_STORAGE (déjà déclarée pour maxSdkVersion 29).
///  - **iOS / autres** : dossier documents de l'app (accessible via Fichiers).

const _publicFolder = 'Alanya';

/// Télécharge un fichier puis l'ouvre. Retourne le chemin/URI local.
Future<String?> downloadUrl(String url, String filename) async {
  final path = await _downloadTo(url, filename);
  if (path != null) {
    await openLocalFile(path);
  }
  return path;
}

/// Télécharge seulement (sans ouvrir).
Future<String?> downloadOnly(String url, String filename) => _downloadTo(url, filename);

/// Ouvre un fichier local avec l'application système appropriée.
Future<void> openLocalFile(String path) async => _openFile(path);

/// Cache "app-privé" : consulte le stockage privé de l'app (pour éviter de
/// re-télécharger un fichier qu'on a déjà lu, sans polluer le stockage public).
/// Utilisé par le viewer PDF/vidéo qui a besoin d'un fichier local temporaire.
Future<String?> getCachedFile(String filename) async {
  try {
    final dir = await _appCacheDir();
    final path = '${dir.path}/$filename';
    if (await File(path).exists()) return path;
    return null;
  } catch (_) {
    return null;
  }
}

/// Télécharge dans le cache app-privé et retourne le chemin.
/// Utile pour ouvrir un PDF/vidéo sans le sauvegarder définitivement.
Future<String?> downloadToCache(String url, String filename) async {
  try {
    final existing = await getCachedFile(filename);
    if (existing != null) return existing;

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final dir = await _appCacheDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/$filename';
    await File(path).writeAsBytes(response.bodyBytes);
    return path;
  } catch (e) {
    debugPrint('[Alanya] downloadToCache erreur: $e');
    return null;
  }
}

// ============================================================================
// Impl interne
// ============================================================================

Future<String?> _downloadTo(String url, String filename) async {
  try {
    debugPrint('[Alanya] Téléchargement: $filename');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      debugPrint('[Alanya] Échec HTTP ${response.statusCode}');
      return null;
    }
    final bytes = response.bodyBytes;
    debugPrint('[Alanya] Reçu ${bytes.length} octets');

    if (Platform.isAndroid) {
      return _saveAndroid(bytes, filename);
    }
    // iOS / desktop / autres : dossier documents de l'app
    return _saveAppDocuments(bytes, filename);
  } catch (e) {
    debugPrint('[Alanya] Erreur téléchargement: $e');
    return null;
  }
}

/// Sauvegarde Android via MediaStore (dossier public visible).
Future<String?> _saveAndroid(List<int> bytes, String filename) async {
  try {
    // 1) Écrit d'abord dans un fichier temporaire (MediaStore attend un path).
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = File('${tmpDir.path}/$filename');
    await tmpFile.writeAsBytes(bytes);

    // 2) Choisit le dossier public standard selon le type.
    final ext = _ext(filename).toLowerCase();
    final (dirType, dirName) = _mediaStoreTargetFor(ext);

    // 3) Sauvegarde via MediaStore (Android 10+) — aucune permission spéciale.
    MediaStore.appFolder = _publicFolder;
    final mediaStore = MediaStore();
    final info = await mediaStore.saveFile(
      tempFilePath: tmpFile.path,
      dirType: dirType,
      dirName: dirName,
      relativePath: _publicFolder,
    );

    // Nettoyage du fichier temporaire.
    try {
      await tmpFile.delete();
    } catch (_) {}

    if (info == null) {
      debugPrint('[Alanya] MediaStore.saveFile a renvoyé null');
      return null;
    }
    final path = info.uri.toString();
    debugPrint('[Alanya] Sauvegardé dans /${_dirLabel(dirName)}/$_publicFolder : $filename → $path');
    return path;
  } catch (e) {
    debugPrint('[Alanya] Erreur MediaStore, fallback appDocs : $e');
    // Fallback : sauvegarde privée de l'app (au moins ça marche).
    return _saveAppDocuments(bytes, filename);
  }
}

/// Fallback iOS/desktop : dossier documents de l'app, sous-dossier "Alanya".
Future<String?> _saveAppDocuments(List<int> bytes, String filename) async {
  try {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_publicFolder');
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = await _uniquePath(dir.path, filename);
    await File(path).writeAsBytes(bytes);
    debugPrint('[Alanya] Sauvegardé (appDocs) : $path');
    return path;
  } catch (e) {
    debugPrint('[Alanya] Erreur appDocs : $e');
    return null;
  }
}

/// Détermine le couple (DirType, DirName) MediaStore selon l'extension.
/// - Images/Vidéos/Audio → dossiers Pictures/Movies/Music (visibles galerie).
/// - Reste → Download (visible gestionnaire de fichiers).
(DirType, DirName) _mediaStoreTargetFor(String ext) {
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};
  const videos = {'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'};
  const audios = {'mp3', 'wav', 'aac', 'ogg', 'm4a', 'opus', 'flac'};
  if (images.contains(ext)) return (DirType.photo, DirName.pictures);
  if (videos.contains(ext)) return (DirType.video, DirName.movies);
  if (audios.contains(ext)) return (DirType.audio, DirName.music);
  return (DirType.download, DirName.download);
}

String _dirLabel(DirName d) {
  switch (d) {
    case DirName.pictures:
      return 'Pictures';
    case DirName.movies:
      return 'Movies';
    case DirName.music:
      return 'Music';
    case DirName.download:
      return 'Download';
    default:
      return 'Download';
  }
}

/// Cache app-privé pour les fichiers temporaires (viewer PDF, vidéo).
Future<Directory> _appCacheDir() async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/alanya_media');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

String _ext(String filename) {
  final i = filename.lastIndexOf('.');
  return i >= 0 ? filename.substring(i + 1) : '';
}

Future<String> _uniquePath(String dirPath, String filename) async {
  final ext = _ext(filename);
  final nameWithoutExt = ext.isNotEmpty
      ? filename.substring(0, filename.length - ext.length - 1)
      : filename;
  var candidate = '$dirPath/$filename';
  var counter = 1;
  while (await File(candidate).exists()) {
    final suffix =
        ext.isNotEmpty ? '$nameWithoutExt($counter).$ext' : '$nameWithoutExt($counter)';
    candidate = '$dirPath/$suffix';
    counter++;
  }
  return candidate;
}

Future<void> _openFile(String pathOrUri) async {
  try {
    // Sur Android post-MediaStore, on récupère un content:// URI, pas un path.
    // url_launcher gère les 2 types.
    final uri = pathOrUri.startsWith('content://') || pathOrUri.startsWith('file://')
        ? Uri.parse(pathOrUri)
        : Uri.file(pathOrUri);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('[Alanya] Aucune app pour ouvrir : $pathOrUri');
    }
  } catch (e) {
    debugPrint('[Alanya] Erreur ouverture : $e');
  }
}
