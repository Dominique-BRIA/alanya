import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_filex/open_filex.dart';
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

/// Rapporteur de progression : fraction reçue entre 0 et 1, ou `null` quand le
/// serveur ne dit pas la taille attendue.
///
/// 🔴 **LA PROGRESSION N'EXISTAIT PAS DU TOUT** (19/08/2026). `http.get` rend la
/// réponse ENTIÈRE d'un coup : entre le premier octet et le dernier, il n'y a
/// rien à observer. Une vidéo de 40 Mo produisait donc un écran figé, puis un
/// fichier. Compter demande une requête en FLUX, pas un booléen de plus.
typedef SurProgression = void Function(double? fraction);

/// Télécharge un fichier puis l'ouvre. Retourne le chemin/URI local.
Future<String?> downloadUrl(String url, String filename,
    {SurProgression? surProgression}) async {
  final path = await _downloadTo(url, filename, surProgression);
  if (path != null) {
    await openLocalFile(path);
  }
  return path;
}

/// Télécharge seulement (sans ouvrir).
Future<String?> downloadOnly(String url, String filename,
        {SurProgression? surProgression}) =>
    _downloadTo(url, filename, surProgression);

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
Future<String?> downloadToCache(String url, String filename,
    {SurProgression? surProgression}) async {
  try {
    final existing = await getCachedFile(filename);
    if (existing != null) return existing;

    final bytes = await _octetsAvecProgression(url, surProgression);
    if (bytes == null) return null;

    final dir = await _appCacheDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/$filename';
    await File(path).writeAsBytes(bytes);
    return path;
  } catch (e) {
    debugPrint('[Alanya] downloadToCache erreur: $e');
    return null;
  }
}

// ============================================================================
// Impl interne
// ============================================================================

Future<String?> _downloadTo(
    String url, String filename, SurProgression? surProgression) async {
  try {
    debugPrint('[Alanya] Téléchargement: $filename');
    final bytes = await _octetsAvecProgression(url, surProgression);
    if (bytes == null) return null;
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

/// Lit le corps de la réponse EN FLUX, en rapportant l'avancement.
///
/// ⚠️ `Content-Length` peut manquer — compression à la volée, transfert par
/// morceaux. On rapporte alors `null` plutôt qu'un pourcentage inventé : une
/// barre indéterminée dit la vérité, une barre figée à 0 % fait croire à une
/// panne. Les deux cas doivent donc remonter jusqu'à l'affichage.
///
/// ⚠️ Le rapport est LIMITÉ À UN PAR POUR CENT. Sans cela, un fichier de 40 Mo
/// déclencherait des milliers de rafraîchissements — et, une fois branché sur
/// les notifications, autant d'allers-retours vers le système.
Future<List<int>?> _octetsAvecProgression(
    String url, SurProgression? surProgression) async {
  final client = http.Client();
  try {
    final requete = http.Request('GET', Uri.parse(url));
    final reponse = await client.send(requete);
    if (reponse.statusCode != 200) {
      debugPrint('[Alanya] Échec HTTP ${reponse.statusCode}');
      return null;
    }
    final total = reponse.contentLength;
    final octets = <int>[];
    var recus = 0;
    var dernierPourcent = -1;
    surProgression?.call(total == null || total <= 0 ? null : 0);
    await for (final morceau in reponse.stream) {
      octets.addAll(morceau);
      recus += morceau.length;
      if (surProgression == null) continue;
      if (total == null || total <= 0) continue;
      final pourcent = (recus * 100 ~/ total).clamp(0, 100);
      if (pourcent != dernierPourcent) {
        dernierPourcent = pourcent;
        surProgression(pourcent / 100);
      }
    }
    return octets;
  } finally {
    client.close();
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
    // content:// (MediaStore) ou http(s):// → url_launcher.
    if (pathOrUri.startsWith('content://') || pathOrUri.startsWith('http')) {
      final uri = Uri.parse(pathOrUri);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    // Chemin de fichier réel → OpenFilex (Intent ACTION_VIEW via FileProvider),
    // fiable sur Android moderne où les URI file:// sont bloquées. C'est le
    // « passage de main à l'OS » pour les types sans lecteur intégré.
    final path = pathOrUri.startsWith('file://')
        ? Uri.parse(pathOrUri).toFilePath()
        : pathOrUri;
    final res = await OpenFilex.open(path);
    if (res.type != ResultType.done) {
      debugPrint('[Alanya] OpenFilex: ${res.type} ${res.message}');
    }
  } catch (e) {
    debugPrint('[Alanya] Erreur ouverture : $e');
  }
}
