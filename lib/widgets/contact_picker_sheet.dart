import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../features/contacts/contacts_repository.dart';
import '../models/contact.dart';
import '../theme/alanya_theme.dart';
import 'avatar_circle.dart';

/// Bottom sheet pour sélectionner des contacts avec recherche
/// et possibilité de saisir un numéro manuellement.
///
/// Retourne une liste de numéros publics sélectionnés.
class ContactPickerSheet extends StatefulWidget {
  const ContactPickerSheet({
    super.key,
    this.title = "Sélectionner des contacts",
    this.confirmLabel = "Valider",
    this.excludeNumbers = const [],
  });

  final String title;
  final String confirmLabel;
  final List<String> excludeNumbers; // numéros à exclure (déjà membres)

  /// Affiche le sélecteur et retourne la liste de numéros sélectionnés.
  static Future<List<String>?> show(
    BuildContext context, {
    String title = "Sélectionner des contacts",
    String confirmLabel = "Valider",
    List<String> excludeNumbers = const [],
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ContactPickerSheet(
        title: title,
        confirmLabel: confirmLabel,
        excludeNumbers: excludeNumbers,
      ),
    );
  }

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet> {
  List<Contact>? _contacts;
  bool _loading = true;
  bool _error = false;
  final Set<String> _selectedNumbers = {};
  String _search = '';
  bool _showManualInput = false;
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await context.read<ContactsRepository>().list();
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _loading = false;
        });
      }
    } on ApiException catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  void _toggleNumber(String number) {
    setState(() {
      if (_selectedNumbers.contains(number)) {
        _selectedNumbers.remove(number);
      } else {
        _selectedNumbers.add(number);
      }
    });
  }

  void _addManualNumber() {
    final number = _manualCtrl.text.trim();
    if (number.isNotEmpty && !_selectedNumbers.contains(number)) {
      setState(() {
        _selectedNumbers.add(number);
        _manualCtrl.clear();
        _showManualInput = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filtre les contacts
    final allContacts = (_contacts ?? [])
        .where((c) => !widget.excludeNumbers.contains(c.publicNumber))
        .toList();
    final filtered = _search.isEmpty
        ? allContacts
        : allContacts.where((c) {
            final q = _search.toLowerCase();
            return c.displayName.toLowerCase().contains(q) ||
                c.publicNumber.contains(q);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
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

          // En-tête avec titre + bouton valider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _selectedNumbers.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selectedNumbers.toList()),
                  child: Text(
                    _selectedNumbers.isEmpty
                        ? widget.confirmLabel
                        : "${widget.confirmLabel} (${_selectedNumbers.length})",
                    style: TextStyle(
                      color: _selectedNumbers.isEmpty
                          ? mutedOf(context, AlanyaColors.grey400)
                          : accentOf(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Barre de recherche + bouton saisie manuelle
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v.trim()),
                    decoration: InputDecoration(
                      hintText: "Rechercher un contact…",
                      prefixIcon: Icon(Icons.search,
                          size: 20, color: mutedOf(context, AlanyaColors.grey400)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
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
                const SizedBox(width: 8),
                // Bouton saisie manuelle
                IconButton(
                  onPressed: () =>
                      setState(() => _showManualInput = !_showManualInput),
                  icon: Icon(
                    _showManualInput ? Icons.keyboard_hide : Icons.dialpad,
                    color: accentOf(context),
                  ),
                  tooltip: "Saisir un numéro",
                ),
              ],
            ),
          ),

          // Champ saisie manuelle (visible quand _showManualInput == true)
          if (_showManualInput)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: "Alanya ID (ex: 67641599)",
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne)),
                        ),
                      ),
                      onSubmitted: (_) => _addManualNumber(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addManualNumber,
                    icon: Icon(Icons.add_circle,
                        color: accentOf(context)),
                  ),
                ],
              ),
            ),

          // Contacts sélectionnés (chips)
          if (_selectedNumbers.isNotEmpty)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _selectedNumbers.map((n) {
                  // Trouve le contact correspondant
                  final contact = allContacts
                      .where((c) => c.publicNumber == n)
                      .toList();
                  final name = contact.isNotEmpty
                      ? contact.first.displayName
                      : n;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Chip(
                      avatar: AvatarCircle(
                        name: name,
                        avatarUrl:
                            contact.isNotEmpty ? contact.first.avatarUrl : null,
                        radius: 12,
                        backgroundColor: AlanyaColors.gold,
                      ),
                      label: Text(name, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => _toggleNumber(n),
                      backgroundColor:
                          accentOf(context).withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  );
                }).toList(),
              ),
            ),

          // Liste des contacts
          Expanded(
            child: _loading
                ? Center(
                    child:
                        CircularProgressIndicator(color: accentOf(context)))
                : _error
                    ? Center(
                        child: Text("Erreur de chargement",
                            style: TextStyle(color: mutedOf(context, AlanyaColors.grey500))))
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                                _search.isEmpty
                                    ? "Aucun contact"
                                    : "Aucun résultat",
                                style:
                                    TextStyle(color: mutedOf(context, AlanyaColors.grey400))))
                        : ListView.builder(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final c = filtered[i];
                              final selected =
                                  _selectedNumbers.contains(c.publicNumber);
                              return ListTile(
                                leading: AvatarCircle(
                                  name: c.displayName,
                                  avatarUrl: c.avatarUrl,
                                  radius: 20,
                                  backgroundColor: AlanyaColors.gold,
                                ),
                                title: Text(c.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                subtitle: Text(c.publicNumber,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: mutedOf(context, AlanyaColors.grey500))),
                                trailing: selected
                                    ? Icon(Icons.check_circle,
                                        color: accentOf(context))
                                    : Icon(Icons.radio_button_unchecked,
                                        color: themed(context, light: AlanyaColors.grey300, dark: AlanyaColors.ligne)),
                                onTap: () =>
                                    _toggleNumber(c.publicNumber),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
