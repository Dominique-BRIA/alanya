import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/chargement.dart';
import '../../../core/api_client.dart';
import '../../../widgets/back_app_bar.dart';
import '../../account/account_repository.dart';
import '../../status/screens/audience_statuts_screen.dart';

/// Réglages de confidentialité : confirmations de lecture + visibilité « vu à ».
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  int _readReceipts = 1;

  /// Le chiffrement de bout en bout, pour TOUT le compte. Actif par défaut.
  bool _chiffrementActif = true;

  /// « Interdire qu'on me renomme » (18/10/2026).
  bool _nomVerrouille = false;
  bool _appelsContactsSeulement = false;

  /// Connexion web en deux étapes (18/10/2026) ; imposée : agent d'entreprise.
  bool _deuxEtapes = false;
  bool _deuxEtapesImposee = false;
  int _lastSeenVisibility = 2;
  bool _loading = true;

  // 🔴 CE N'EST PLUS UNE CONSTANTE, et ça ne peut plus en être une : les
  // libellés dépendent de la langue, qui se lit dans le contexte. Une
  // `static const Map` fige ses valeurs à la compilation — elle serait restée
  // en français quelle que soit la langue choisie.
  //
  // L'ordre des entrées porte l'affichage de la liste : 2, puis 1, puis 0, du
  // plus ouvert au plus fermé. Une `Map` littérale le préserve.
  Map<int, String> _visibilityLabels(BuildContext context) => {
        2: tr(context, 'audience_everyone'),
        1: tr(context, 'audience_contacts'),
        0: tr(context, 'audience_nobody'),
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<AccountRepository>();
    void appliquer(Map p) => setState(() {
          _readReceipts = p["readReceipts"] ?? 1;
          _lastSeenVisibility = p["lastSeenVisibility"] ?? 2;
          _chiffrementActif = (p["chiffrementActif"] ?? 1) == 1;
          _nomVerrouille = (p["nomVerrouille"] ?? 0) == 1;
          _appelsContactsSeulement = (p["appelsContactsSeulement"] ?? 0) == 1;
          _deuxEtapes = (p["deuxEtapes"] ?? 0) == 1;
          _deuxEtapesImposee = (p["deuxEtapesImposee"] ?? 0) == 1;
          _loading = false;
        });
    // Cache d'abord : les réglages gardés s'affichent aussitôt (18/10/2026).
    try {
      final copie = await ApiClient.copieSeulement(() => repo.getPrivacy());
      if (mounted && _loading) appliquer(copie);
    } catch (_) {}
    if (mounted) setState(() => _miseAJour = true);
    try {
      final p = await repo.getPrivacy();
      if (!mounted) return;
      appliquer(p);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      if (mounted) setState(() => _miseAJour = false);
    }
  }

  bool _miseAJour = false;

  Future<void> _save({
    int? readReceipts,
    int? lastSeenVisibility,
    bool? chiffrementActif,
    bool? nomVerrouille,
    bool? appelsContactsSeulement,
    bool? deuxEtapes,
  }) async {
    try {
      await context.read<AccountRepository>().setPrivacy(
            readReceipts: readReceipts,
            lastSeenVisibility: lastSeenVisibility,
            chiffrementActif: chiffrementActif,
            nomVerrouille: nomVerrouille,
            appelsContactsSeulement: appelsContactsSeulement,
            deuxEtapes: deuxEtapes,
          );
    } catch (_) {
      if (mounted) showAppSnackBar(tr(context, 'priv_save_failed'));
    }
  }

  void _pickVisibility() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr(context, 'priv_last_seen'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Divider(height: 1),
          ..._visibilityLabels(context).entries.map((e) {
            final selected = e.key == _lastSeenVisibility;
            return ListTile(
              title: Text(e.value),
              trailing: selected
                  ? const Icon(Icons.check, color: AlanyaColors.terracotta)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _lastSeenVisibility = e.key);
                _save(lastSeenVisibility: e.key);
              },
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'set_privacy')),
      body: _loading
          ? const SqueletteListe(lignes: 5, avatar: false)
          : ListView(
              children: [
                BarreMiseAJour(visible: _miseAJour),
                /*
                 * ══════ LE SEUL ENDROIT OÙ L'ON PARLE DU CHIFFREMENT ══════
                 *
                 * 🔴 DÉCISION DU USER, 12/10/2026 : le chiffrement est actif
                 * par défaut et se coupe ICI, pour toute l'application — plus
                 * conversation par conversation.
                 *
                 * ⚠️ LA DESCRIPTION DIT CE QUE LE RÉGLAGE NE FAIT PAS : le
                 * couper n'ouvre pas les conversations déjà chiffrées, car le
                 * chiffrement ne se défait pas. Laisser croire le contraire
                 * ferait croire à quelqu'un qu'il parle en clair alors qu'il
                 * est chiffré, ou l'inverse — le pire des malentendus.
                 */
                SwitchListTile(
                  secondary: Icon(Icons.shield_outlined,
                      color: themed(context,
                          light: AlanyaColors.forest,
                          dark: AlanyaColors.indigoLight)),
                  title: Text(tr(context, 'e2ee_reglage_label')),
                  subtitle: Text(tr(
                      context,
                      _chiffrementActif
                          ? 'e2ee_reglage_on'
                          : 'e2ee_reglage_off')),
                  value: _chiffrementActif,
                  onChanged: (v) {
                    setState(() => _chiffrementActif = v);
                    _save(chiffrementActif: v);
                  },
                ),
                const Divider(height: 1),
                // Demande du patron (18/10/2026) : ceux qui m'enregistrent
                // gardent le nom de mon profil, sans pouvoir en mettre un autre.
                SwitchListTile(
                  secondary: Icon(Icons.badge_outlined,
                      color: themed(context,
                          light: AlanyaColors.forest,
                          dark: AlanyaColors.indigoLight)),
                  title: Text(tr(context, 'priv_name_lock')),
                  subtitle: Text(tr(context, 'priv_name_lock_sub')),
                  value: _nomVerrouille,
                  onChanged: (v) {
                    setState(() => _nomVerrouille = v);
                    _save(nomVerrouille: v);
                  },
                ),
                const Divider(height: 1),
                // Demande du user (29/10/2026) : seuls mes contacts enregistrés
                // peuvent m'appeler. Le serveur refuse les autres avant de sonner.
                SwitchListTile(
                  secondary: Icon(Icons.phone_locked_outlined,
                      color: themed(context,
                          light: AlanyaColors.forest,
                          dark: AlanyaColors.indigoLight)),
                  title: Text(tr(context, 'priv_calls_contacts_only')),
                  subtitle: Text(tr(context, 'priv_calls_contacts_only_sub')),
                  value: _appelsContactsSeulement,
                  onChanged: (v) {
                    setState(() => _appelsContactsSeulement = v);
                    _save(appelsContactsSeulement: v);
                  },
                ),
                const Divider(height: 1),
                // Demande du patron (18/10/2026) : « juste le mot de passe, ce
                // n'est pas solide ». Grisé pour un compte d'entreprise, pour
                // qui le serveur l'impose.
                SwitchListTile(
                  secondary: Icon(Icons.phonelink_lock_outlined,
                      color: themed(context,
                          light: AlanyaColors.forest,
                          dark: AlanyaColors.indigoLight)),
                  title: Text(tr(context, 'priv_2fa')),
                  subtitle: Text(tr(context,
                      _deuxEtapesImposee ? 'priv_2fa_impose' : 'priv_2fa_sub')),
                  value: _deuxEtapes || _deuxEtapesImposee,
                  onChanged: _deuxEtapesImposee
                      ? null
                      : (v) {
                          setState(() => _deuxEtapes = v);
                          _save(deuxEtapes: v);
                        },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.done_all,
                      color: themed(context,
                          light: AlanyaColors.forest,
                          dark: AlanyaColors.indigoLight)),
                  title: Text(tr(context, 'priv_read_receipts')),
                  subtitle: Text(
                      tr(context, 'priv_read_receipts_sub')),
                  value: _readReceipts == 1,
                  onChanged: (v) {
                    setState(() => _readReceipts = v ? 1 : 0);
                    _save(readReceipts: v ? 1 : 0);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.visibility_outlined,
                      color: themed(context,
                          light: AlanyaColors.terracotta,
                          dark: AlanyaColors.terracottaNuit)),
                  title: Text(tr(context, 'priv_last_seen')),
                  subtitle:
                      Text(_visibilityLabels(context)[_lastSeenVisibility] ?? tr(context, 'audience_everyone')),
                  trailing: Icon(Icons.chevron_right,
                      color: themed(context,
                          light: Colors.grey, dark: AlanyaColors.craie2)),
                  onTap: _pickVisibility,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.radio_button_checked,
                      color: themed(context,
                          light: AlanyaColors.forest,
                          dark: AlanyaColors.terracottaNuit)),
                  title: Text(tr(context, 'priv_status')),
                  subtitle: Text(tr(context, 'priv_status_sub')),
                  trailing: Icon(Icons.chevron_right,
                      color: themed(context,
                          light: Colors.grey, dark: AlanyaColors.craie2)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AudienceStatutsScreen(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(context, 'priv_nobody_hint'),
                    style: TextStyle(
                        fontSize: 12,
                        color: themed(context,
                            light: AlanyaColors.grey500,
                            dark: AlanyaColors.craie2)),
                  ),
                ),
              ],
            ),
    );
  }
}
