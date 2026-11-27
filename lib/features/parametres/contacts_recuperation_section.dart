import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_snackbar.dart';
import '../../core/realtime_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/e2ee/e2ee_contacts_recuperation.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../contacts/contacts_repository.dart';

/// LES CONTACTS DE RÉCUPÉRATION, DANS L'ÉCRAN DE SAUVEGARDE (27/11/2026).
///
/// 🔴 JUMELLE DE `STAGE-WEB/app/(protected)/settings/contacts-recuperation.tsx`.
///
/// Trois personnes de confiance ; deux suffisent à rendre l'accès aux anciens
/// messages. Seuls les contacts qui ont une clé de compte (leur sauvegarde est
/// active) peuvent être choisis : la part leur est scellée.
class ContactsRecuperationSection extends StatefulWidget {
  const ContactsRecuperationSection({super.key});

  @override
  State<ContactsRecuperationSection> createState() => _ContactsRecuperationSectionState();
}

class _ContactsRecuperationSectionState extends State<ContactsRecuperationSection> {
  bool _actif = false;
  List<MonContactRecuperation> _contacts = const [];
  bool _occupe = false;
  StreamSubscription<Map<String, dynamic>>? _signaux;

  @override
  void dispose() {
    _signaux?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _relire());
    // Un contact vient d'accepter ou de refuser : l'état change sous nos yeux.
    _signaux = context.read<RealtimeClient>().events.listen((e) {
      if (mounted && e['type'] == 'e2ee_recuperation' && e['quoi'] == 'invitation_repondue') _relire();
    });
  }

  ContactsRecuperation? get _service {
    final pile = context.e2ee;
    return pile == null ? null : ContactsRecuperation(pile);
  }

  Future<void> _relire() async {
    final s = _service;
    if (s == null) return;
    try {
      final r = await s.mesContacts();
      if (mounted) {
        setState(() {
          _actif = r.actif;
          _contacts = r.contacts;
        });
      }
    } catch (_) {}
  }

  Future<void> _choisir() async {
    final s = _service;
    if (s == null) return;
    final contacts = (await context.read<ContactsRepository>().list()).where((c) => !c.isBlocked).toList();
    final cles = await s.clesDeCompte(contacts.map((c) => c.userId).toList()).catchError((_) => <String, ({int version, String publique})>{});
    if (!mounted) return;
    final coches = <String>{..._contacts.map((c) => c.contactId)};
    final choisis = await showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: Text('${tr(c, 'recup_choisir_titre')} (${coches.length}/3)'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final ct in contacts)
                  CheckboxListTile(
                    value: coches.contains(ct.userId),
                    onChanged: !cles.containsKey(ct.userId) ||
                            (!coches.contains(ct.userId) && coches.length >= 3)
                        ? null
                        : (v) => maj(() => v == true ? coches.add(ct.userId) : coches.remove(ct.userId)),
                    title: Text(ct.displayName),
                    subtitle: cles.containsKey(ct.userId) ? null : Text(tr(c, 'recup_sans_cle')),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'arch_plus_tard'))),
            FilledButton(
              onPressed: coches.length == 3 ? () => Navigator.pop(c, coches.toList()) : null,
              child: Text(tr(c, 'recup_valider')),
            ),
          ],
        ),
      ),
    );
    if (choisis == null || !mounted) return;
    setState(() => _occupe = true);
    try {
      await s.confier(choisis);
      if (mounted) showAppSnackBar(tr(context, 'recup_enregistre'));
      await _relire();
    } catch (_) {
      if (mounted) showAppSnackBar(tr(context, 'recup_erreur'));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _retirer() async {
    final s = _service;
    if (s == null) return;
    final oui = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'recup_retirer')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'arch_plus_tard'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'recup_retirer'))),
        ],
      ),
    );
    if (oui != true) return;
    setState(() => _occupe = true);
    try {
      await s.retirer();
      await _relire();
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  String _etat(BuildContext c, String e) => switch (e) {
        'accepte' => tr(c, 'recup_etat_accepte'),
        'refuse' => tr(c, 'recup_etat_refuse'),
        _ => tr(c, 'recup_etat_invite'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.groups_outlined, size: 20),
              const SizedBox(width: 8),
              Text(tr(context, 'recup_titre'), style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            Text(tr(context, 'recup_explication'), style: const TextStyle(fontSize: 13)),
            if (_contacts.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final c in _contacts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c.etat == 'accepte' ? Icons.check_circle : Icons.schedule,
                    color: c.etat == 'accepte' ? const Color(0xFF2C6B34) : Colors.grey,
                    size: 20,
                  ),
                  title: Text(c.nom ?? '—'),
                  trailing: Text(_etat(context, c.etat), style: theme.textTheme.bodySmall),
                ),
              Text(
                tr(context, _actif ? 'recup_actif' : 'recup_inactif'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _occupe ? null : _choisir,
              child: Text(tr(context, _contacts.isEmpty ? 'recup_choisir' : 'recup_changer')),
            ),
            if (_contacts.isNotEmpty)
              TextButton(
                onPressed: _occupe ? null : _retirer,
                child: Text(tr(context, 'recup_retirer')),
              ),
          ],
        ),
      ),
    );
  }
}
