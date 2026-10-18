import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Les images des badges, GARDÉES SUR LE TÉLÉPHONE.
///
/// 🐛 « LE BADGE ALANYA NE DOIT PLUS DISPARAÎTRE » (user, 18/10/2026). Le
/// badge se dessinait avec `Image.network` : aucune copie sur le téléphone, une
/// seule en mémoire, perdue à chaque lancement. Hors ligne ou sur un réseau
/// lent, le badge n'apparaissait pas ; il surgissait ensuite au milieu de la
/// ligne, ou jamais si le téléchargement échouait.
///
/// 🔴 CACHE D'ABORD : l'image gardée s'affiche tout de suite, et elle est
/// revérifiée UNE FOIS par lancement, en arrière-plan — la console peut
/// changer l'image d'un badge sans changer son adresse.
///
/// ⚠️ DE PETITES IMAGES, PEU NOMBREUSES (une par type de badge) : les préférences
/// suffisent, en base64. Pas de fichier, et le web fonctionne pareil.
class ImagesBadges {
  ImagesBadges._();

  static const _prefixe = 'badge_image.';

  /// Au-delà, ce n'est plus une icône : on ne la garde pas.
  static const _tailleMax = 256 * 1024;

  static final Map<String, Uint8List> _memoire = {};
  static final Set<String> _revalidees = {};
  static final Map<String, Future<Uint8List?>> _enCours = {};

  /// L'image déjà en mémoire, sans attendre — `null` si pas encore lue.
  static Uint8List? enMemoire(String url) => _memoire[url];

  /// L'image de [url] : mémoire, puis téléphone, puis réseau.
  static Future<Uint8List?> lire(String url) {
    final connue = _memoire[url];
    if (connue != null) {
      _revalider(url);
      return Future.value(connue);
    }
    return _enCours[url] ??= _lire(url).whenComplete(() => _enCours.remove(url));
  }

  /// Prépare les images de ces badges (préchargement de session).
  static Future<void> prechauffer(Iterable<String> urls) async {
    for (final url in urls.toSet()) {
      await lire(url);
    }
  }

  static Future<Uint8List?> _lire(String url) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('$_prefixe$url');
      if (s != null) {
        final octets = base64Decode(s);
        _memoire[url] = octets;
        _revalider(url);
        return octets;
      }
    } catch (_) {
      // Copie illisible : on la remplace par le réseau.
    }
    return _telecharger(url);
  }

  static void _revalider(String url) {
    if (!_revalidees.add(url)) return;
    _telecharger(url);
  }

  static Future<Uint8List?> _telecharger(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 ||
          r.bodyBytes.isEmpty ||
          r.bodyBytes.length > _tailleMax) {
        return _memoire[url];
      }
      _memoire[url] = r.bodyBytes;
      _revalidees.add(url);
      final p = await SharedPreferences.getInstance();
      await p.setString('$_prefixe$url', base64Encode(r.bodyBytes));
      return r.bodyBytes;
    } catch (_) {
      // Hors ligne : on garde ce qu'on avait, et la revérification se refera
      // au prochain lancement.
      _revalidees.remove(url);
      return _memoire[url];
    }
  }
}
