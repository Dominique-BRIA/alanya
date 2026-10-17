import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TRADUCTION AUTOMATIQUE des messages reçus.
///
/// Quand elle est active, un message reçu dans une autre langue est traduit dès
/// son arrivée : plus besoin d'appuyer sur « Traduire ».
///
/// 🔴 ÉTEINTE PAR DÉFAUT. Personne n'est traduit sans l'avoir demandé, et
/// surtout : la traduction sur l'appareil suppose des modèles de langue de
/// plusieurs dizaines de mégaoctets. Une fonction qui s'allume toute seule
/// pourrait en réclamer le jour où l'on écrit à quelqu'un d'une nouvelle langue.
///
/// ⚠️ RÉGLAGE D'APPAREIL, JAMAIS SYNCHRONISÉ AU COMPTE — même raison : les
/// modèles sont installés PAR TÉLÉPHONE. Un réglage qui suivrait le compte
/// promettrait sur un appareil une traduction que seul un autre saurait rendre.
///
/// Même patron que `NotificationSettings` : singleton synchrone, lu par des
/// déclencheurs qui n'ont pas de `BuildContext` sous la main, et un
/// [ValueNotifier] pour que l'interrupteur des réglages suive.
class TraductionAuto {
  TraductionAuto._();
  static final TraductionAuto instance = TraductionAuto._();

  static const _cle = 'traduction_auto';

  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  bool get activee => active.value;

  /// À appeler au démarrage, avant le premier fil de discussion.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      active.value = prefs.getBool(_cle) ?? false;
    } catch (_) {
      // Préférences illisibles : on reste éteint. Le défaut prudent est celui
      // qui ne télécharge rien.
    }
  }

  Future<void> definir(bool valeur) async {
    if (active.value == valeur) return;
    active.value = valeur;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cle, valeur);
    } catch (_) {
      // L'écriture a échoué : le réglage vaut pour cette session.
    }
  }
}
