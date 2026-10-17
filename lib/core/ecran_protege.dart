import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ÉCRAN PROTÉGÉ — interdit la capture d'écran pendant l'affichage d'un
/// message à vue unique (Android : `FLAG_SECURE`, voir `MainActivity.kt`).
///
/// Posé à l'ouverture du visionneur, retiré à sa fermeture : sur toute
/// l'application, il empêcherait aussi de capturer une conversation ordinaire,
/// et masquerait l'application dans l'aperçu des tâches récentes.
///
/// ⚠️ NE LÈVE JAMAIS. Sur une plateforme sans le canal (web, iOS, tests),
/// l'appel ne fait rien : la vue unique reste une vue unique côté serveur, la
/// capture n'est simplement pas bloquée.
class EcranProtege {
  static const _canal = MethodChannel('alanya/ecran_protege');

  static Future<void> activer() => _appeler('activer');
  static Future<void> desactiver() => _appeler('desactiver');

  static Future<void> _appeler(String methode) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _canal.invokeMethod<bool>(methode);
    } catch (e) {
      debugPrint('[ecran-protege] $methode impossible : $e');
    }
  }
}
