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

  /// Ce que voit le moteur natif : images reçues, visages trouvés, erreurs.
  /// Nul si indisponible.
  static Future<Map<String, dynamic>?> etat() async {
    if (!disponible) return null;
    try {
      final m = await _canal.invokeMethod<Map>('etat');
      return m?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// La clé du message qui explique pourquoi l'effet ne se voit pas, ou nul
  /// si tout va bien. [etat] vient de [EffetsVideo.etat], lu ~2 s après le
  /// choix.
  ///
  /// 🔴 « RIEN NE CHANGE À L'IMAGE » (18/10/2026) : le natif rend l'image
  /// d'origine à la moindre difficulté, sans rien dire. Ce diagnostic dit
  /// laquelle — c'est ce qu'il faut demander à celui qui teste.
  static String? diagnostic(Map<String, dynamic>? etat) {
    if (etat == null || etat['effet'] == 'aucun') return null;
    if (etat['detecteur'] != null) return 'fx_diag_detecteur';
    if ((etat['images'] as num? ?? 0) == 0) return 'fx_diag_images';
    if ((etat['visages'] as num? ?? 0) > 0) return null;
    if (etat['erreur'] != null) return 'fx_diag_erreur';
    return 'fx_diag_visage';
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
