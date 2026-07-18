import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service biométrie local — gère l'authentification par empreinte/visage.
/// La préférence est stockée localement sur l'appareil (SharedPreferences).
/// La vérification utilise le package `local_auth` (Secure Enclave de l'OS).
class BiometricService {
  static const _prefKey = 'biometric_enabled';
  static final _auth = LocalAuthentication();

  /// Vérifie si l'appareil supporte la biométrie.
  static Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si la biométrie est disponible (empreinte ou visage configuré).
  static Future<bool> canCheckBiometrics() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si la biométrie est activée dans les préférences locales.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Active ou désactive la biométrie dans les préférences locales.
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  /// Demande l'authentification biométrique.
  /// Retourne `true` si l'utilisateur s'est authentifié avec succès.
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Déverrouiller Alanya',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (_) {
      return false;
    }
  }
}
