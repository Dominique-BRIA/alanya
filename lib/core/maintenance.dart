import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'server_config.dart';

/// LE MODE MAINTENANCE (24/10/2026).
///
/// Le serveur refuse l'application par un 503 `MAINTENANCE` pendant une
/// maintenance réglée depuis la console. [ApiClient] le signale ici ; l'écran
/// [EcranMaintenance] recouvre alors toute l'application, et interroge
/// `GET /api/maintenance` (la seule route qui répond pendant ce temps) pour
/// savoir quand reprendre.
class Maintenance {
  Maintenance._();

  /// Vrai tant que le serveur est en maintenance.
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  static Timer? _sondage;

  /// Appelé par le client HTTP à la réception d'un 503 `MAINTENANCE`.
  static void signaler() {
    if (active.value) return;
    active.value = true;
    _sondage?.cancel();
    _sondage = Timer.periodic(const Duration(seconds: 20), (_) => verifier());
  }

  /// Interroge le serveur ; lève la maintenance s'il l'a levée.
  static Future<void> verifier() async {
    try {
      final r = await http
          .get(Uri.parse('${ServerConfig.apiBase}/api/maintenance'))
          .timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && d['maintenance'] == false) {
        _sondage?.cancel();
        _sondage = null;
        active.value = false;
      }
    } catch (_) {
      // Hors ligne ou serveur indisponible : on réessaiera au tour suivant.
    }
  }
}
