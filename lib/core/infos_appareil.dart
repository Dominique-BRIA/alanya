import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// La marque et le modèle de cet appareil (« samsung SM-A515F »).
///
/// Lus côté Android (`Build.MANUFACTURER` et `Build.MODEL`, canal
/// `alanya/appareil` de `MainActivity`) : le filigrane d'un document sensible
/// les porte (18/10/2026). Ailleurs, ou si le canal ne répond pas, un libellé
/// générique — jamais d'échec.
class InfosAppareil {
  InfosAppareil._();

  static const _canal = MethodChannel('alanya/appareil');
  static String? _memoire;

  static Future<String> marqueModele() async {
    final connu = _memoire;
    if (connu != null) return connu;
    String valeur;
    try {
      valeur = (await _canal.invokeMethod<String>('marqueModele'))?.trim() ?? '';
    } catch (_) {
      valeur = '';
    }
    if (valeur.isEmpty) {
      valeur = kIsWeb ? 'Navigateur' : defaultTargetPlatform.name;
    }
    return _memoire = valeur;
  }
}
