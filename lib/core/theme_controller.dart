import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/alanya_theme.dart';

/// Les thèmes proposés à l'utilisateur.
///
/// Flutter n'en connaît que trois (`ThemeMode.system/light/dark`) et Alanya en
/// a désormais quatre entrées. On garde donc notre propre énumération, et
/// [ThemeController] la traduit en `themeMode` + `darkTheme` pour MaterialApp.
enum ChoixTheme { systeme, clair, blanc, nuit, noir }

/// Contrôleur de thème : Système, Clair, Nuit ou Noir. Persisté localement.
class ThemeController extends ChangeNotifier {
  ThemeController();

  static const _prefsKey = 'alanya_theme_mode';

  ChoixTheme _choix = ChoixTheme.clair;
  ChoixTheme get choix => _choix;

  /// Dernier thème sombre retenu, pour la bascule rapide de l'accueil.
  ///
  /// Sans cette mémoire, quelqu'un qui a choisi Noir, bascule en clair puis
  /// revient au sombre se retrouverait en Nuit : son réglage aurait disparu
  /// sans qu'il ait rien demandé.
  ChoixTheme _dernierSombre = ChoixTheme.nuit;

  /// Symétrique du précédent : quelqu'un qui a choisi Blanc doit y revenir,
  /// pas atterrir sur Clair.
  ChoixTheme _dernierClair = ChoixTheme.clair;

  /// Bascule clair ↔ sombre, utilisée par le bouton de l'écran d'accueil.
  Future<void> basculerClairSombre(bool actuellementSombre) async {
    if (actuellementSombre) {
      if (_choix == ChoixTheme.nuit || _choix == ChoixTheme.noir) {
        _dernierSombre = _choix;
      }
      await setChoix(_dernierClair);
    } else {
      if (_choix == ChoixTheme.clair || _choix == ChoixTheme.blanc) {
        _dernierClair = _choix;
      }
      await setChoix(_dernierSombre);
    }
  }

  /// Ce que MaterialApp reçoit comme `themeMode`.
  ///
  /// Nuit et Noir valent tous deux « sombre » : c'est [themeSombre] qui
  /// détermine lequel des deux s'applique.
  ThemeMode get mode {
    switch (_choix) {
      case ChoixTheme.clair:
      case ChoixTheme.blanc:
        return ThemeMode.light;
      case ChoixTheme.nuit:
      case ChoixTheme.noir:
        return ThemeMode.dark;
      case ChoixTheme.systeme:
        return ThemeMode.system;
    }
  }

  /// Le thème clair effectivement passé à MaterialApp.
  ///
  /// Même mécanique que [themeSombre] : MaterialApp n'accepte qu'UN thème
  /// clair, c'est donc ici qu'on tranche entre Clair et Blanc. En mode
  /// Système, c'est **Clair** qui s'applique, pour la même raison que Nuit
  /// côté sombre : le thème historique reste le défaut.
  ThemeData get themeClair =>
      _choix == ChoixTheme.blanc ? AlanyaTheme.blanc : AlanyaTheme.light;

  /// Le thème sombre effectivement passé à MaterialApp.
  ///
  /// En mode Système, c'est **Nuit** qui s'applique quand le téléphone bascule.
  /// Noir reste un choix explicite : c'est un parti pris visuel fort, il serait
  /// surprenant de l'imposer à quelqu'un qui a seulement demandé « suis mon
  /// système ».
  ThemeData get themeSombre =>
      _choix == ChoixTheme.noir ? AlanyaTheme.noir : AlanyaTheme.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    // Premier lancement : pas de préférence → mode clair par défaut.
    _choix = saved == null ? ChoixTheme.clair : _decode(saved);
    // Repartir du thème sombre réellement en cours, sinon la première bascule
    // depuis Noir ramènerait Nuit.
    if (_choix == ChoixTheme.nuit || _choix == ChoixTheme.noir) {
      _dernierSombre = _choix;
    }
    if (_choix == ChoixTheme.clair || _choix == ChoixTheme.blanc) {
      _dernierClair = _choix;
    }
    notifyListeners();
  }

  Future<void> setChoix(ChoixTheme choix) async {
    if (_choix == choix) return;
    _choix = choix;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(choix));
  }

  /// Lit la préférence enregistrée.
  ///
  /// Les valeurs `light` / `dark` / `system` sont celles d'AVANT le troisième
  /// thème. Elles doivent continuer à être comprises, sinon tous ceux qui ont
  /// déjà l'application repartiraient en clair à la mise à jour — un réglage
  /// perdu sans explication.
  static ChoixTheme _decode(String v) {
    switch (v) {
      case 'clair':
      case 'light':
        return ChoixTheme.clair;
      case 'blanc':
        return ChoixTheme.blanc;
      case 'nuit':
      case 'dark':
        return ChoixTheme.nuit;
      case 'noir':
        return ChoixTheme.noir;
      case 'systeme':
      case 'system':
        return ChoixTheme.systeme;
      default:
        return ChoixTheme.clair;
    }
  }

  static String _encode(ChoixTheme c) {
    switch (c) {
      case ChoixTheme.clair:
        return 'clair';
      case ChoixTheme.blanc:
        return 'blanc';
      case ChoixTheme.nuit:
        return 'nuit';
      case ChoixTheme.noir:
        return 'noir';
      case ChoixTheme.systeme:
        return 'systeme';
    }
  }

  /// Libellé lisible pour l'UI.
  static String label(ChoixTheme c) {
    switch (c) {
      case ChoixTheme.clair:
        return 'Clair';
      case ChoixTheme.blanc:
        return 'Blanc';
      case ChoixTheme.nuit:
        return 'Nuit';
      case ChoixTheme.noir:
        return 'Noir';
      case ChoixTheme.systeme:
        return 'Système';
    }
  }

  /// Courte explication sous le libellé, dans les réglages. « Nuit » et
  /// « Noir » ne se distinguent pas d'eux-mêmes.
  static String description(ChoixTheme c) {
    switch (c) {
      case ChoixTheme.clair:
        return 'Fond crème, accents terre cuite';
      case ChoixTheme.blanc:
        return 'Fond blanc, accent teal, terre cuite en second';
      case ChoixTheme.nuit:
        return 'Indigo profond, motif discret';
      case ChoixTheme.noir:
        return 'Noir intégral, économise la batterie sur écran OLED';
      case ChoixTheme.systeme:
        return 'Suit le réglage du téléphone';
    }
  }

  static IconData icone(ChoixTheme c) {
    switch (c) {
      case ChoixTheme.clair:
        return Icons.light_mode;
      case ChoixTheme.blanc:
        return Icons.wb_sunny_outlined;
      case ChoixTheme.nuit:
        return Icons.dark_mode;
      case ChoixTheme.noir:
        return Icons.contrast;
      case ChoixTheme.systeme:
        return Icons.brightness_auto;
    }
  }
}
