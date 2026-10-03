import 'package:shared_preferences/shared_preferences.dart';

import 'debug_overlay.dart';

/// Verse dans l'overlay de débogage les traces écrites par le code NATIF du
/// chip vert (`OngoingCallChip.kt`).
///
/// POURQUOI CE DÉTOUR. Les décisions qui font apparaître — ou non — le chip se
/// prennent toutes en Kotlin : autorisation de démarrer un service de premier
/// plan, acceptation du type `phoneCall` par Android, pose effective de la
/// notification. Ces traces partent normalement dans `adb logcat`, inaccessible
/// sans câble. Le natif les recopie donc dans les préférences Flutter, et cette
/// fonction les remonte à l'écran.
///
/// ⚠️ `reload()` est INDISPENSABLE. `SharedPreferences` garde un cache mémoire
/// constitué au premier `getInstance()` ; or le natif écrit APRÈS, pendant
/// l'appel. Sans relecture, on lirait l'instantané d'avant le décroché et
/// l'écran resterait vide — on conclurait à tort que le natif n'a rien tracé.
///
/// La clé est vidée après lecture : les traces ne doivent pas se rejouer à
/// chaque appel suivant, sinon on ne sait plus quelle ligne appartient à quel
/// appel.
Future<void> verserTracesChip() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final brut = prefs.getString('chip_diag');
    if (brut == null || brut.isEmpty) return;
    for (final ligne in brut.split('\n')) {
      if (ligne.isNotEmpty) DebugOverlay.log('CHIP $ligne');
    }
    await prefs.remove('chip_diag');
  } catch (e) {
    // Préférences illisibles : on le dit plutôt que de laisser croire que le
    // natif n'a rien écrit. Un diagnostic muet est pire que pas de diagnostic.
    DebugOverlay.log('CHIP ⚠️ lecture des traces impossible : $e');
  }
}
