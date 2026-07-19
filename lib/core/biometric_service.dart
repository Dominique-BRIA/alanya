import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static const _prefKey = 'biometric_enabled';
  static final _auth = LocalAuthentication();

  static Future<bool> isDeviceSupported() async {
    try { return await _auth.isDeviceSupported(); } catch (_) { return false; }
  }

  static Future<bool> canCheckBiometrics() async {
    try { return (await _auth.getAvailableBiometrics()).isNotEmpty; } catch (_) { return false; }
  }

  static Future<bool> isAvailable() async {
    try { return await isDeviceSupported() || await canCheckBiometrics(); } catch (_) { return false; }
  }

  static Future<bool> isEnabled() async {
    try { final prefs = await SharedPreferences.getInstance(); return prefs.getBool(_prefKey) ?? false; } catch (_) { return false; }
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  /// Empreinte/visage uniquement (biometricOnly: true)
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
    } catch (e) {
      debugPrint('[Biometric] Error: $e');
      return false;
    }
  }

  /// Avec fallback PIN/pattern (biometricOnly: false)
  static Future<bool> authenticateWithFallback() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Déverrouiller Alanya',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('[Biometric] Error: $e');
      return false;
    }
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try { return await _auth.getAvailableBiometrics(); } catch (_) { return []; }
  }

  static Future<String> getBiometricDescription() async {
    final types = await getAvailableBiometrics();
    if (types.isEmpty) return "Non disponible";
    if (types.contains(BiometricType.face)) return "Reconnaissance faciale";
    if (types.contains(BiometricType.fingerprint)) return "Empreinte digitale";
    if (types.contains(BiometricType.iris)) return "Reconnaissance irienne";
    return "Biométrie";
  }
}
