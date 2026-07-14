import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocale {
  final String code;
  final String nativeName;
  final String flag;
  const AppLocale(this.code, this.nativeName, this.flag);
}

/// Contrôleur de langue pour Alanya.
/// Langue par défaut : français (fr)
class LocaleController extends ChangeNotifier {
  LocaleController();

  static const _prefsKey = 'alanya_locale';

  static const List<AppLocale> supported = [
    AppLocale('fr', 'Français', '🇫🇷'),
    AppLocale('en', 'English', '🇬🇧'),
    AppLocale('zh', '中文', '🇨🇳'),
    AppLocale('es', 'Español', '🇪🇸'),
    AppLocale('de', 'Deutsch', '🇩🇪'),
    AppLocale('pt', 'Português', '🇵🇹'),
    AppLocale('ru', 'Русский', '🇷🇺'),
    AppLocale('sv', 'Svenska', '🇸🇪'),
    AppLocale('no', 'Norsk', '🇳🇴'),
  ];

  static List<String> get supportedLocales => supported.map((e) => e.code).toList();

  Locale _locale = const Locale('fr');
  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey) ?? 'fr';
    if (supportedLocales.contains(code)) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  Future<void> setLocale(String code) async {
    if (!supportedLocales.contains(code)) return;
    if (_locale.languageCode == code) return;
    _locale = Locale(code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }

  bool get isFrench => _locale.languageCode == 'fr';
}
