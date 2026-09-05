import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/alanya_id_formatter.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../contacts_repository.dart';
import '../services/phone_sync_service.dart';

/// Écran de synchronisation du répertoire téléphonique.
/// Scanne les contacts du téléphone, détecte les numéros Alanya (6 ou 8 chiffres),
/// vérifie lesquels ont un compte, et permet de les ajouter en un tap.
class PhoneSyncScreen extends StatefulWidget {
  const PhoneSyncScreen({super.key});

  @override
  State<PhoneSyncScreen> createState() => _PhoneSyncScreenState();
}

class _PhoneSyncScreenState extends State<PhoneSyncScreen> {
  bool _scanning = false;
  String _statusMsg = "";
  PhoneSyncResult? _result;

  // Contacts sélectionnés pour import (publicNumber → true/false)
  final Map<String, bool> _selected = {};
  bool _importing = false;

  late final PhoneSyncService _service;

  @override
  void initState() {
    super.initState();
    final repo = context.read<ContactsRepository>();
    _service = PhoneSyncService(repo.matchNumbers);
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _result = null;
      _selected.clear();
      _statusMsg = tr(context, 'sync_starting');
    });

    final result = await _service.sync(
      onProgress: (msg) {
        if (mounted) setState(() => _statusMsg = msg);
      },
    );

    if (!mounted) return;

    // Pré-sélectionne tous les contacts non encore ajoutés
    if (result.isSuccess) {
      for (final m in result.matches) {
        if (!m.alanyaUser.alreadyContact) {
          _selected[m.alanyaUser.publicNumber] = true;
        }
      }
    }

    setState(() {
      _scanning = false;
      _result = result;
      _statusMsg = "";
    });
  }

  Future<void> _importSelected() async {
    final toAdd = _result?.matches
            .where((m) =>
                _selected[m.alanyaUser.publicNumber] == true &&
                !m.alanyaUser.alreadyContact)
            .toList() ??
        [];

    if (toAdd.isEmpty) {
      showAppSnackBar(tr(context, 'sync_none_selected'));
      return;
    }

    setState(() => _importing = true);

    final repo = context.read<ContactsRepository>();
    int added = 0;
    int errors = 0;

    for (final match in toAdd) {
      try {
        await repo.add(
          match.alanyaUser.publicNumber,
          alias: match.phoneName != match.alanyaUser.publicNumber
              ? match.phoneName
              : null,
        );
        added++;
      } on ApiException catch (e) {
        if (e.code == "ALREADY_CONTACT") {
          added++; // compte quand même
        } else {
          errors++;
        }
      } catch (_) {
        errors++;
      }
    }

    if (!mounted) return;
    setState(() => _importing = false);

    final msg = errors == 0
        ? trN(context, 'sync_added', added)
        : tr(context, 'sync_added_with_errors', {'a': '$added', 'e': '$errors'});

    showAppSnackBar(msg);
    if (added > 0) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'import_from_phone')),
      body: SafeArea(child: _body()),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _body() {
    if (_scanning) return _scanningView();

    final result = _result;
    if (result == null) return _introView();

    switch (result.status) {
      case PhoneSyncStatus.permissionDenied:
        return _messageView(
          icon: Icons.contacts_outlined,
          color: Colors.orange,
          title: tr(context, 'sync_perm_denied'),
          subtitle:
              tr(context, 'sync_perm_body'),
          action: _settingsButton(),
        );
      case PhoneSyncStatus.empty:
        return _messageView(
          icon: Icons.person_off_outlined,
          title: tr(context, 'sync_book_empty'),
          subtitle: tr(context, 'sync_book_empty_body'),
        );
      case PhoneSyncStatus.noAlanyaNumbers:
        return _messageView(
          icon: Icons.search_off,
          title: tr(context, 'sync_no_id'),
          subtitle:
              tr(context, 'sync_no_id_body'),
          action: _retryButton(),
        );
      case PhoneSyncStatus.noMatches:
        return _messageView(
          icon: Icons.group_off_outlined,
          title: tr(context, 'sync_no_match'),
          subtitle:
              trN(context, 'sync_scanned_none', result.totalScanned),
          action: _retryButton(),
        );
      case PhoneSyncStatus.error:
        return _messageView(
          icon: Icons.cloud_off,
          color: dangerOf(context),
          title: tr(context, 'error'),
          subtitle: result.errorMessage ?? tr(context, 'error_unknown'),
          action: _retryButton(),
        );
      case PhoneSyncStatus.success:
        return _matchList(result);
    }
  }

  Widget _introView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: positiveOf(context).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.contacts, size: 56, color: positiveOf(context)),
            ),
            const SizedBox(height: 24),
            Text(
              tr(context, 'sync_title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              tr(context, 'sync_explain'),
              style: TextStyle(
                  color: mutedOf(context, Colors.black54), height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'sync_privacy'),
              style: TextStyle(
                  color: faintOf(context, Colors.black38),
                  fontSize: 12,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.search),
                label: Text(tr(context, 'sync_scan')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: positiveOf(context),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanningView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: accentOf(context)),
            const SizedBox(height: 24),
            Text(
              _statusMsg,
              style: TextStyle(color: mutedOf(context, Colors.black54)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchList(PhoneSyncResult result) {
    final matches = result.matches;
    final newOnes = matches.where((m) => !m.alanyaUser.alreadyContact).length;

    return Column(
      children: [
        // En-tête résumé
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: positiveOf(context).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: positiveOf(context).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: positiveOf(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trN(context, 'sync_matches', matches.length),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      trN(context, 'sync_new_scanned', newOnes, {'total': '${result.totalScanned}'}),
                      style: TextStyle(
                          color: mutedOf(context, Colors.black54),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _scan,
                child: Text(tr(context, 'sync_rescan')),
              ),
            ],
          ),
        ),

        // Liste
        Expanded(
          child: ListView.separated(
            itemCount: matches.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _matchTile(matches[i]),
          ),
        ),
      ],
    );
  }

  Widget _matchTile(PhoneContactMatch match) {
    final user = match.alanyaUser;
    final isAlready = user.alreadyContact;
    final isSelected = _selected[user.publicNumber] ?? false;
    final displayName = user.pseudo ?? match.phoneName;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isAlready
            ? themed(context,
                light: Colors.grey.shade300,
                dark: surfacesOf(context).surfaceHaute)
            : AlanyaColors.gold,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
          style: TextStyle(
              color: isAlready ? mutedOf(context, Colors.grey) : Colors.white),
        ),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isAlready ? mutedOf(context, Colors.grey) : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'home_alanya_id', {'id': formatAlanyaId(user.publicNumber)}),
              style: alanyaIdStyleOf(context)),
          if (match.phoneName != displayName)
            Text(
              tr(context, 'sync_in_book', {'nom': match.phoneName}),
              style: TextStyle(
                  fontSize: 11, color: faintOf(context, Colors.black38)),
            ),
          if (isAlready)
            Text(
              tr(context, 'sync_already'),
              style: TextStyle(fontSize: 12, color: positiveOf(context)),
            ),
        ],
      ),
      trailing: isAlready
          ? Icon(Icons.check, color: positiveOf(context))
          : Checkbox(
              value: isSelected,
              activeColor: positiveOf(context),
              onChanged: _importing
                  ? null
                  : (v) =>
                      setState(() => _selected[user.publicNumber] = v ?? false),
            ),
      onTap: isAlready || _importing
          ? null
          : () => setState(() => _selected[user.publicNumber] = !isSelected),
    );
  }

  Widget? _bottomBar() {
    final result = _result;
    if (result == null || !result.isSuccess || _scanning) return null;

    final selectedCount = _selected.values.where((v) => v).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                (_importing || selectedCount == 0) ? null : _importSelected,
            style: ElevatedButton.styleFrom(
              backgroundColor: positiveOf(context),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _importing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    selectedCount == 0
                        ? tr(context, 'sync_select')
                        : trN(context, 'sync_add_n', selectedCount),
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _messageView({
    required IconData icon,
    Color? color,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 64, color: color ?? faintOf(context, Colors.black26)),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(
                    color: mutedOf(context, Colors.black54), height: 1.5),
                textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }

  Widget _retryButton() => ElevatedButton.icon(
        onPressed: _scan,
        icon: const Icon(Icons.refresh),
        label: Text(tr(context, 'retry')),
        style: ElevatedButton.styleFrom(backgroundColor: accentOf(context)),
      );

  Widget _settingsButton() => ElevatedButton.icon(
        onPressed: () => openAppSettings(),
        icon: const Icon(Icons.settings),
        label: Text(tr(context, 'open_settings')),
        style: ElevatedButton.styleFrom(backgroundColor: accentOf(context)),
      );
}
