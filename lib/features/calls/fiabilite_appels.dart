import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/alanya_theme.dart';
import '../../widgets/back_app_bar.dart';

/*
 * FIABILITÉ DES APPELS ENTRANTS (07/11/2026).
 *
 * Qu'un appel s'affiche tout seul à l'écran ne dépend pas que du code : cinq
 * réglages du téléphone peuvent l'en empêcher, chacun en silence. Le symptôme
 * observé — le téléphone sonne, mais il faut dérouler le panneau pour trouver
 * l'appel, ou une bannière passe et disparaît — vient de l'un d'eux.
 *
 * - Notifications de l'application coupées : rien ne s'affiche du tout.
 * - Canal « appels » abaissé (par l'utilisateur ou le fabricant) : l'appel
 *   n'apparaît plus à l'écran, seulement dans le panneau.
 * - « Plein écran » refusé (Android 14 et plus, souvent par défaut) :
 *   téléphone verrouillé, l'écran ne s'allume plus.
 * - « Afficher par-dessus les autres applications » refusé : téléphone
 *   déverrouillé, l'écran d'appel ne peut pas passer au premier plan — il
 *   reste une bannière (voir AffichageAppel.kt).
 * - Optimisation de batterie : un téléphone endormi reçoit l'appel en
 *   retard, ou pas du tout.
 *
 * Aucune de ces autorisations ne s'accorde par le code : il faut ouvrir la
 * bonne page de réglages. Cet écran fait le point et y mène ; le rappel au
 * démarrage revient tant qu'un point critique manque, au lieu d'une question
 * posée une seule fois puis oubliée.
 */

/// L'état des réglages dont dépend l'affichage d'un appel.
class EtatAffichageAppels {
  const EtatAffichageAppels({
    required this.notifications,
    required this.canalAppels,
    required this.pleinEcran,
    required this.superposition,
    required this.batterie,
    required this.fabricant,
  });

  final bool notifications;
  final bool canalAppels;
  final bool pleinEcran;
  final bool superposition;
  final bool batterie;
  final String fabricant;

  /// Un réglage SANS LEQUEL un appel peut ne pas s'afficher.
  bool get critiqueManquant =>
      !notifications || !canalAppels || !pleinEcran || !superposition;

  /// Fabricants connus pour brider l'affichage en arrière-plan avec des
  /// réglages à eux (démarrage automatique, écran de verrouillage, fenêtres
  /// en arrière-plan).
  bool get fabricantRestrictif => const {
        'xiaomi', 'redmi', 'poco', 'tecno', 'infinix', 'itel', 'oppo',
        'realme', 'oneplus', 'vivo', 'huawei', 'honor',
      }.contains(fabricant);
}

class FiabiliteAppels {
  FiabiliteAppels._();

  static const _canal = MethodChannel('com.alanya/call_native');
  static const _cleRappel = 'fiabilite_appels_rappel';

  static Future<EtatAffichageAppels?> lire() async {
    if (!Platform.isAndroid) return null;
    try {
      final r = await _canal.invokeMapMethod<String, dynamic>('etatAffichageAppels');
      if (r == null) return null;
      return EtatAffichageAppels(
        notifications: r['notifications'] == true,
        canalAppels: r['canalAppels'] == true,
        pleinEcran: r['pleinEcran'] == true,
        superposition: r['superposition'] == true,
        batterie: r['batterie'] == true,
        fabricant: r['fabricant']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> ouvrir(String quoi) async {
    try {
      return await _canal.invokeMethod<bool>('ouvrirReglageAppels', {'quoi': quoi}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Au démarrage, une fois connecté : si un réglage CRITIQUE manque, on le
  /// dit et on propose de le régler. « Plus tard » ne fait taire le rappel
  /// que pour la journée — un appel manqué demain coûte plus cher qu'un
  /// rappel de plus.
  static Future<void> verifierAuDemarrage(BuildContext context) async {
    try {
      final etat = await lire();
      if (etat == null || !etat.critiqueManquant) return;
      final prefs = await SharedPreferences.getInstance();
      final dernier = prefs.getInt(_cleRappel) ?? 0;
      final maintenant = DateTime.now().millisecondsSinceEpoch;
      if (maintenant - dernier < const Duration(hours: 24).inMilliseconds) return;
      await prefs.setInt(_cleRappel, maintenant);
      if (!context.mounted) return;
      final regler = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.phone_in_talk_outlined, size: 32),
          title: Text(tr(ctx, 'callrel_dialog_title')),
          content: Text(tr(ctx, 'callrel_dialog_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, 'later')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, 'callrel_dialog_go')),
            ),
          ],
        ),
      );
      if (regler == true && context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const EcranFiabiliteAppels(),
        ));
      }
    } catch (_) {
      // Une vérification qui échoue ne doit jamais bloquer l'application.
    }
  }
}

/// La liste des réglages, chacun avec son état et le bouton qui y mène.
/// Relue à chaque retour dans l'application : on revient des réglages
/// système, l'état a changé.
class EcranFiabiliteAppels extends StatefulWidget {
  const EcranFiabiliteAppels({super.key});

  @override
  State<EcranFiabiliteAppels> createState() => _EcranFiabiliteAppelsState();
}

class _EcranFiabiliteAppelsState extends State<EcranFiabiliteAppels>
    with WidgetsBindingObserver {
  EtatAffichageAppels? _etat;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _relire();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _relire();
  }

  Future<void> _relire() async {
    final e = await FiabiliteAppels.lire();
    if (!mounted) return;
    setState(() {
      _etat = e;
      _charge = true;
    });
  }

  Widget _ligne({
    required IconData icone,
    required String titre,
    required String explication,
    required bool ok,
    required String quoi,
    bool recommande = false,
  }) {
    final couleurEtat = ok
        ? AlanyaColors.forest
        : (recommande ? AlanyaColors.terracottaLight : Colors.red);
    return ListTile(
      leading: Icon(icone, color: AlanyaColors.terracotta),
      title: Text(titre),
      subtitle: Text(explication),
      isThreeLine: true,
      trailing: ok
          ? Icon(Icons.check_circle, color: couleurEtat)
          : FilledButton.tonal(
              onPressed: () => FiabiliteAppels.ouvrir(quoi),
              child: Text(tr(context, 'callrel_fix')),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _etat;
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'callrel_screen_title')),
      body: !_charge
          ? const Center(child: CircularProgressIndicator())
          : e == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr(context, 'callrel_unavailable'),
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        tr(context,
                            e.critiqueManquant ? 'callrel_intro' : 'callrel_all_good'),
                      ),
                    ),
                    _ligne(
                      icone: Icons.notifications_active_outlined,
                      titre: tr(context, 'callrel_notif_title'),
                      explication: tr(context, 'callrel_notif_body'),
                      ok: e.notifications,
                      quoi: 'notifications',
                    ),
                    _ligne(
                      icone: Icons.ring_volume_outlined,
                      titre: tr(context, 'callrel_channel_title'),
                      explication: tr(context, 'callrel_channel_body'),
                      ok: e.canalAppels,
                      quoi: 'canalAppels',
                    ),
                    _ligne(
                      icone: Icons.screen_lock_portrait_outlined,
                      titre: tr(context, 'callrel_fullscreen_title'),
                      explication: tr(context, 'callrel_fullscreen_body'),
                      ok: e.pleinEcran,
                      quoi: 'pleinEcran',
                    ),
                    _ligne(
                      icone: Icons.picture_in_picture_outlined,
                      titre: tr(context, 'callrel_overlay_title'),
                      explication: tr(context, 'callrel_overlay_body'),
                      ok: e.superposition,
                      quoi: 'superposition',
                    ),
                    _ligne(
                      icone: Icons.battery_saver_outlined,
                      titre: tr(context, 'callrel_battery_title'),
                      explication: tr(context, 'callrel_battery_body'),
                      ok: e.batterie,
                      quoi: 'batterie',
                      recommande: true,
                    ),
                    if (e.fabricantRestrictif)
                      ListTile(
                        leading: const Icon(Icons.phone_android_outlined,
                            color: AlanyaColors.terracotta),
                        title: Text(tr(context, 'callrel_oem_title')),
                        subtitle: Text(tr(context, 'callrel_oem_body')),
                        isThreeLine: true,
                        trailing: FilledButton.tonal(
                          onPressed: () => FiabiliteAppels.ouvrir('fabricant'),
                          child: Text(tr(context, 'callrel_fix')),
                        ),
                      ),
                  ],
                ),
    );
  }
}
