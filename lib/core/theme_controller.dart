import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contrôleur de thème : Clair (défaut), Sombre ou Système. Persisté localement.
class ThemeController extends ChangeNotifier {
  ThemeController();

  static const _prefsKey = 'alanya_theme_mode';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    // Premier lancement : pas de préférence sauvegardée → mode clair par défaut.
    if (saved == null) {
      _mode = ThemeMode.light;
    } else {
      _mode = _decode(saved);
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(mode));
  }

  static ThemeMode _decode(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Libellé lisible pour l'UI.
  static String label(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'Clair';
      case ThemeMode.dark:
        return 'Sombre';
      case ThemeMode.system:
        return 'Système';
    }
  }
}
