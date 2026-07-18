import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
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

  /// Vérifie si la biométrie est disponible (empreinte ou visage configuré).
  static Future<bool> canCheckBiometrics() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
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
  /// Retourne `true` si l'utilisateur s'est authentifié avec succès.
  static Future<bool> authenticate({String reason = 'Déverrouiller Alanya'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // autorise le PIN/schéma en fallback
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );
    } on PlatformException catch (e) {
      // Erreur spécifique : biométrie désactivée ou verrouillée
      if (e.code == auth_error.notAvailable) return false;
      if (e.code == auth_error.notEnrolled) return false;
      if (e.code == auth_error.lockedOut) return false;
      if (e.code == auth_error.permanentlyLockedOut) return false;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Liste les types de biométrie disponibles sur l'appareil.
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Description textuelle des types de biométrie disponibles.
  static Future<String> getBiometricDescription() async {
    final types = await getAvailableBiometrics();
    if (types.isEmpty) return "Non disponible";
    if (types.contains(BiometricType.face)) return "Reconnaissance faciale";
    if (types.contains(BiometricType.fingerprint)) return "Empreinte digitale";
    if (types.contains(BiometricType.iris)) return "Reconnaissance irienne";
    return "Biométrie";
  }
}
