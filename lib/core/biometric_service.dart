import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static const _key = 'biometric_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
