import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/app_theme.dart';
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
      _statusMsg = "Démarrage…";
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
            .where((m) => _selected[m.alanyaUser.publicNumber] == true && !m.alanyaUser.alreadyContact)
            .toList() ??
        [];

    if (toAdd.isEmpty) {
      showAppSnackBar("Aucun contact sélectionné");
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
          alias: match.phoneName != match.alanyaUser.publicNumber ? match.phoneName : null,
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
        ? "$added contact${added > 1 ? 's' : ''} ajouté${added > 1 ? 's' : ''} ✓"
        : "$added ajouté${added > 1 ? 's' : ''}, $errors erreur${errors > 1 ? 's' : ''}";

    showAppSnackBar(msg);
    if (added > 0) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Importer depuis le téléphone"),
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
          title: "Permission refusée",
          subtitle: "Alanya a besoin d'accéder à ton répertoire pour trouver tes amis.\nVa dans les Paramètres → Applications → Alanya → Autorisations.",
          action: _settingsButton(),
        );
      case PhoneSyncStatus.empty:
        return _messageView(
          icon: Icons.person_off_outlined,
          title: "Répertoire vide",
          subtitle: "Ton répertoire téléphonique ne contient aucun contact.",
        );
      case PhoneSyncStatus.noAlanyaNumbers:
        return _messageView(
          icon: Icons.search_off,
          title: "Aucun numéro Alanya détecté",
          subtitle: "Aucun de tes contacts n'a de numéro à 6 chiffres dans son profil.\nLes numéros Alanya sont des numéros à 6 ou 8 chiffres (ex: 123456 ou 12345678).",
          action: _retryButton(),
        );
      case PhoneSyncStatus.noMatches:
        return _messageView(
          icon: Icons.group_off_outlined,
          title: "Aucun contact sur Alanya",
          subtitle: "${result.totalScanned} numéro${result.totalScanned > 1 ? 's' : ''} vérifié${result.totalScanned > 1 ? 's' : ''}.\nAucun de tes contacts n'a encore de compte Alanya.",
          action: _retryButton(),
        );
      case PhoneSyncStatus.error:
        return _messageView(
          icon: Icons.cloud_off,
          color: Colors.red,
          title: "Erreur",
          subtitle: result.errorMessage ?? "Erreur inconnue.",
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
                color: AppColors.forest.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.contacts, size: 56, color: AppColors.forest),
            ),
            const SizedBox(height: 24),
            const Text(
              "Trouve tes amis sur Alanya",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              "Alanya va scanner ton répertoire téléphonique, extraire les numéros à 6 ou 8 chiffres et vérifier lesquels ont un compte.",
              style: TextStyle(color: Colors.black54, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              "Aucune donnée n'est stockée. Seuls les numéros à 6 ou 8 chiffres sont envoyés au serveur.",
              style: TextStyle(color: Colors.black38, fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.search),
                label: const Text("Scanner mon répertoire"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.forest,
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
            const CircularProgressIndicator(color: AppColors.terracotta),
            const SizedBox(height: 24),
            Text(
              _statusMsg,
              style: const TextStyle(color: Colors.black54),
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
            color: AppColors.forest.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.forest.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.forest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${matches.length} contact${matches.length > 1 ? 's' : ''} sur Alanya",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      "$newOnes nouveau${newOnes > 1 ? 'x' : ''} · ${result.totalScanned} numéros scannés",
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _scan,
                child: const Text("Rescanner"),
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
        backgroundColor: isAlready ? Colors.grey.shade300 : AppColors.clay,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
          style: TextStyle(color: isAlready ? Colors.grey : Colors.white),
        ),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isAlready ? Colors.grey : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Numéro Alanya : ${user.publicNumber}"),
          if (match.phoneName != displayName)
            Text(
              "Dans ton répertoire : ${match.phoneName}",
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
          if (isAlready)
            const Text(
              "Déjà dans ton répertoire Alanya",
              style: TextStyle(fontSize: 12, color: AppColors.forest),
            ),
        ],
      ),
      trailing: isAlready
          ? const Icon(Icons.check, color: AppColors.forest)
          : Checkbox(
              value: isSelected,
              activeColor: AppColors.forest,
              onChanged: _importing
                  ? null
                  : (v) => setState(() => _selected[user.publicNumber] = v ?? false),
            ),
      onTap: isAlready || _importing
          ? null
          : () => setState(() => _selected[user.publicNumber] = !isSelected),
    );
  }

  Widget? _bottomBar() {
    final result = _result;
    if (result == null || !result.isSuccess || _scanning) return null;

    final selectedCount =
        _selected.values.where((v) => v).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_importing || selectedCount == 0) ? null : _importSelected,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.forest,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _importing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    selectedCount == 0
                        ? "Sélectionne des contacts"
                        : "Ajouter $selectedCount contact${selectedCount > 1 ? 's' : ''}",
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
            Icon(icon, size: 64, color: color ?? Colors.black26),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: const TextStyle(color: Colors.black54, height: 1.5),
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
        label: const Text("Réessayer"),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.terracotta),
      );

  Widget _settingsButton() => ElevatedButton.icon(
        onPressed: () => openAppSettings(),
        icon: const Icon(Icons.settings),
        label: const Text("Ouvrir les paramètres"),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.terracotta),
      );
}
