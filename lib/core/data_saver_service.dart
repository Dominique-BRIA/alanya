import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode « économie de données » (réseau faible / data mobile).
///
/// Quand il est activé, les médias **pas encore en cache** ne sont PAS
/// téléchargés automatiquement : l'utilisateur doit toucher pour télécharger.
/// Les médias déjà en cache s'affichent normalement (c'est gratuit).
///
/// Singleton avec valeur synchrone (lue par [CachedMedia] sans provider) +
/// persistance SharedPreferences. `enabled` est un [ValueNotifier] pour que
/// l'écran de réglages réagisse.
class DataSaverService {
  DataSaverService._();
  static final DataSaverService instance = DataSaverService._();

  static const _key = 'data_saver_enabled';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  bool get isOn => enabled.value;

  /// À appeler au démarrage de l'app (avant le premier rendu des médias).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}
