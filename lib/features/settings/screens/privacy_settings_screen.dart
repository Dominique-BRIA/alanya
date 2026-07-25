import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../account/account_repository.dart';

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

  static const Map<int, String> _visibilityLabels = {
    2: "Tout le monde",
    1: "Mes contacts",
    0: "Personne",
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
      if (mounted) showAppSnackBar("Échec de l'enregistrement. Réessaie.");
    }
  }

  void _pickVisibility() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text("Vu à et en ligne",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Divider(height: 1),
          ..._visibilityLabels.entries.map((e) {
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
      appBar: backAppBar(context, "Confidentialité"),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.done_all,
                      color: themed(context,
                          light: AlanyaColors.forest,
                          dark: AlanyaColors.indigoLight)),
                  title: const Text("Confirmations de lecture"),
                  subtitle: const Text(
                      "Si désactivé, tu n'envoies plus les coches bleues (et ne les vois plus non plus). Sans effet dans les groupes."),
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
                  title: const Text("Vu à et en ligne"),
                  subtitle:
                      Text(_visibilityLabels[_lastSeenVisibility] ?? "Tout le monde"),
                  trailing: Icon(Icons.chevron_right,
                      color: themed(context,
                          light: Colors.grey, dark: AlanyaColors.craie2)),
                  onTap: _pickVisibility,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "« Personne » masque ta présence à tes interlocuteurs.",
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
