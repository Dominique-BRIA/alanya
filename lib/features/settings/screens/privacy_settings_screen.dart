import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
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
    try {
      final p = await context.read<AccountRepository>().getPrivacy();
      if (!mounted) return;
      setState(() {
        _readReceipts = p["readReceipts"] ?? 1;
        _lastSeenVisibility = p["lastSeenVisibility"] ?? 2;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({int? readReceipts, int? lastSeenVisibility}) async {
    try {
      await context.read<AccountRepository>().setPrivacy(
            readReceipts: readReceipts,
            lastSeenVisibility: lastSeenVisibility,
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
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
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
