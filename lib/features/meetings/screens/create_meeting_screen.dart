import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../models/contact.dart';
import '../../contacts/contacts_repository.dart';
import '../meetings_repository.dart';

/// Écran de création d'une réunion audio ou vidéo.
///
/// Le participant clique sur "Ajouter des participants" pour ouvrir
/// un sélecteur de contacts (liste avec checkboxes).
class CreateMeetingScreen extends StatefulWidget {
  const CreateMeetingScreen({super.key});

  @override
  State<CreateMeetingScreen> createState() => _CreateMeetingScreenState();
}

class _CreateMeetingScreenState extends State<CreateMeetingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _objetCtrl = TextEditingController();
  int _typeMedia = 1; // 1 = audio, 2 = vidéo
  int _duree = 3600; // 1h par défaut
  bool _loading = false;

  // Contacts sélectionnés comme participants
  final List<Contact> _selectedContacts = [];

  @override
  void dispose() {
    _objetCtrl.dispose();
    super.dispose();
  }

  /// Ouvre le sélecteur de contacts (bottom sheet avec checkboxes).
  Future<void> _openContactPicker() async {
    // Charge les contacts
    List<Contact> contacts;
    try {
      contacts = await context.read<ContactsRepository>().list();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible de charger les contacts")),
        );
      }
      return;
    }

    if (contacts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Aucun contact. Ajoute des contacts d'abord.")),
        );
      }
      return;
    }

    // IDs déjà sélectionnés
    final selectedIds = _selectedContacts.map((c) => c.userId).toSet();

    final result = await showModalBottomSheet<List<Contact>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ContactPickerSheet(
        contacts: contacts,
        preSelectedIds: selectedIds,
      ),
    );

    if (result != null && mounted) {
      setState(() => _selectedContacts
        ..clear()
        ..addAll(result));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final numbers = _selectedContacts
          .map((c) => c.publicNumber)
          .where((n) => n.isNotEmpty)
          .toList();

      await context.read<MeetingsRepository>().createMeeting(
            objet: _objetCtrl.text.trim(),
            typeMedia: _typeMedia,
            duree: _duree,
            participantNumbers: numbers.isEmpty ? null : numbers,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Réunion créée !")),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur serveur")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Nouvelle réunion"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Type de réunion ---
              const Text("Type de réunion",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 1,
                    label: Text("Audio"),
                    icon: Icon(Icons.call),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text("Vidéo"),
                    icon: Icon(Icons.videocam),
                  ),
                ],
                selected: {_typeMedia},
                onSelectionChanged: (s) =>
                    setState(() => _typeMedia = s.first),
              ),
              const SizedBox(height: 20),

              // --- Objet ---
              TextFormField(
                controller: _objetCtrl,
                decoration: const InputDecoration(
                  labelText: "Objet de la réunion",
                  prefixIcon: Icon(Icons.subject),
                ),
                validator: (v) =>
                    (v ?? "").trim().isEmpty ? "L'objet est requis" : null,
              ),
              const SizedBox(height: 20),

              // --- Participants ---
              const Text("Participants",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),

              // Bouton pour ouvrir le sélecteur de contacts
              InkWell(
                onTap: _openContactPicker,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: themed(context, light: Colors.white, dark: surfacesOf(context).surface),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_add_outlined,
                          color: accentOf(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedContacts.isEmpty
                              ? "Ajouter des participants"
                              : "${_selectedContacts.length} participant(s) sélectionné(s)",
                          style: TextStyle(
                            color: _selectedContacts.isEmpty
                                ? mutedOf(context, AlanyaColors.grey400)
                                : themed(context, light: AlanyaColors.ink, dark: AlanyaColors.craie),
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: mutedOf(context, AlanyaColors.grey400)),
                    ],
                  ),
                ),
              ),

              // Liste des contacts sélectionnés
              if (_selectedContacts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedContacts.map((c) {
                    return Chip(
                      avatar: AvatarCircle(
                        name: c.displayName,
                        avatarUrl: c.avatarUrl,
                        radius: 14,
                        backgroundColor: AlanyaColors.gold,
                      ),
                      label: Text(c.displayName),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        setState(() =>
                            _selectedContacts.removeWhere((s) => s.userId == c.userId));
                      },
                      backgroundColor: accentOf(context).withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                "Sélectionne tes contacts. Laisse vide pour une réunion solo.",
                style: TextStyle(fontSize: 12, color: mutedOf(context, AlanyaColors.grey500)),
              ),
              const SizedBox(height: 20),

              // --- Durée ---
              const Text("Durée prévue",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _duree,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 900, child: Text("15 minutes")),
                  DropdownMenuItem(value: 1800, child: Text("30 minutes")),
                  DropdownMenuItem(value: 3600, child: Text("1 heure")),
                  DropdownMenuItem(value: 5400, child: Text("1h30")),
                  DropdownMenuItem(value: 7200, child: Text("2 heures")),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _duree = v);
                },
              ),
              const SizedBox(height: 32),

              // --- Bouton créer ---
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add),
                label: const Text("Créer la réunion"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet pour sélectionner des contacts avec checkboxes.
class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({
    required this.contacts,
    required this.preSelectedIds,
  });

  final List<Contact> contacts;
  final Set<String> preSelectedIds;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  late final Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.preSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.contacts
        : widget.contacts.where((c) {
            final q = _search.toLowerCase();
            return c.displayName.toLowerCase().contains(q) ||
                c.publicNumber.contains(q);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            // Poignée
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: themed(context, light: AlanyaColors.grey300, dark: AlanyaColors.ligne),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Titre + bouton valider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text("Sélectionner des participants",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      final selected = widget.contacts
                          .where((c) => _selected.contains(c.userId))
                          .toList();
                      Navigator.pop(context, selected);
                    },
                    child: Text(
                      _selected.isEmpty
                          ? "Valider"
                          : "Valider (${_selected.length})",
                      style: TextStyle(
                        color: accentOf(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Barre de recherche
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => setState(() => _search = v.trim()),
                decoration: InputDecoration(
                  hintText: "Rechercher un contact…",
                  prefixIcon:
                      Icon(Icons.search, size: 20, color: mutedOf(context, AlanyaColors.grey400)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne)),
                  ),
                ),
              ),
            ),
            // Liste des contacts
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        "Aucun contact trouvé",
                        style: TextStyle(color: mutedOf(context, AlanyaColors.grey400)),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final isSelected = _selected.contains(c.userId);
                        return ListTile(
                          leading: AvatarCircle(
                            name: c.displayName,
                            avatarUrl: c.avatarUrl,
                            radius: 20,
                            backgroundColor: AlanyaColors.gold,
                          ),
                          title: Text(c.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(formatAlanyaId(c.publicNumber),
                              style: TextStyle(
                                  fontSize: 12, color: alanyaIdOf(context, AlanyaColors.grey500))),
                          trailing: Checkbox(
                            value: isSelected,
                            activeColor: accentOf(context),
                            onChanged: (_) {
                              setState(() {
                                if (isSelected) {
                                  _selected.remove(c.userId);
                                } else {
                                  _selected.add(c.userId);
                                }
                              });
                            },
                          ),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(c.userId);
                              } else {
                                _selected.add(c.userId);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
