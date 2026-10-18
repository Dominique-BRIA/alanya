import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Les effets de visage pendant un appel vidéo (18/10/2026).
///
/// 🔴 DEMANDE DU PATRON : « comme Snapchat — 100 % gratuit et natif ». Le
/// moteur est Android (`EffetsVisage.kt`) : MediaPipe repère le visage sur le
/// téléphone, l'effet est dessiné sur chaque image AVANT l'envoi — notre
/// interlocuteur le voit, notre aperçu aussi. Aucun service payant, aucun
/// serveur.
///
/// ⚠️ ANDROID SEULEMENT pour l'instant : ailleurs, [disponible] est faux et le
/// bouton ne s'affiche pas.
class EffetsVideo {
  EffetsVideo._();

  static const _canal = MethodChannel('alanya/effets_video');

  /// Les effets proposés, dans l'ordre du sélecteur.
  static const effets = <String>[
    'aucun',
    'barbe',
    'moustache',
    'lunettes',
    'grosse_tete',
    'visage_fin',
  ];

  /// L'effet en cours, pour cocher la bonne vignette.
  static final ValueNotifier<String> actuel = ValueNotifier('aucun');

  static bool get disponible =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Pose [effet] sur la piste caméra [trackId]. Faux si impossible.
  static Future<bool> appliquer(String? trackId, String effet) async {
    if (!disponible || trackId == null) return false;
    try {
      final ok = await _canal
          .invokeMethod<bool>('appliquer', {'trackId': trackId, 'effet': effet});
      if (ok == true) actuel.value = effet;
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Fin d'appel : plus d'effet, tout se libère côté natif.
  static Future<void> retirer() async {
    actuel.value = 'aucun';
    if (!disponible) return;
    try {
      await _canal.invokeMethod('retirer');
    } catch (_) {}
  }
}
