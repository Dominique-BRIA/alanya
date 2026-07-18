import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service biométrie local — gère l'authentification par empreinte/visage.
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

  /// Vérifie si la biométrie est disponible.
  static Future<bool> canCheckBiometrics() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si la biométrie est activée dans les préférences.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Active ou désactive la biométrie.
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  /// Demande l'authentification biométrique.
  static Future<bool> authenticate() async {
    try {
      final canCheck = await canCheckBiometrics();
      if (!canCheck) return false;

      return await _auth.authenticate(
        localizedReason: 'Déverrouiller Alanya',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // autorise le PIN en fallback
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si l'appareil peut utiliser la biométrie (supporté + configuré).
  static Future<bool> isAvailable() async {
    try {
      final supported = await isDeviceSupported();
      final canCheck = await canCheckBiometrics();
      return supported || canCheck;
    } catch (_) {
      return false;
    }
  }
}
