import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../models/contact.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../auth/auth_controller.dart';
import '../../contacts/contacts_repository.dart';
import '../chat_repository.dart';
import 'chat_screen.dart';

/// Création d'un groupe : nom + sélection de contacts du répertoire.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _nameCtrl = TextEditingController();
  List<Contact> _contacts = [];
  final Set<String> _selected = {}; // numéros publics sélectionnés
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final list = await context.read<ContactsRepository>().list();
      if (!mounted) return;
      setState(() {
        _contacts = list.where((c) => !c.isBlocked).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      setState(() => _error = "Donne un nom au groupe (2 caractères min.)");
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = "Sélectionne au moins un contact");
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    final chat = context.read<ChatRepository>();
    try {
      final convId = await chat.createGroup(name, _selected.toList());
      if (!mounted) return;
      final me = context.read<AuthController>().user;
      final names = <String, String>{
        for (final c in _contacts.where((c) => _selected.contains(c.publicNumber)))
          c.userId: c.displayName,
      };
      if (me != null) names[me.id] = me.pseudo ?? me.publicNumber;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(convId: convId, title: name, isGroup: true, memberNames: names),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Création impossible");
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Nouveau groupe"),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.terracotta))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Nom du groupe",
                      prefixIcon: Icon(Icons.groups),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        "Contacts (${_selected.length} sélectionné${_selected.length > 1 ? "s" : ""})",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _contacts.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              "Aucun contact.\nAjoute des contacts avant de créer un groupe.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _contacts.length,
                          itemBuilder: (_, i) {
                            final c = _contacts[i];
                            final checked = _selected.contains(c.publicNumber);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selected.add(c.publicNumber);
                                  } else {
                                    _selected.remove(c.publicNumber);
                                  }
                                });
                              },
                              title: Text(c.displayName),
                              subtitle: Text("Numéro : ${c.publicNumber}"),
                              secondary: CircleAvatar(
                                backgroundColor: AppColors.clay,
                                child: Text(
                                  c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : "?",
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _creating ? null : _create,
                        icon: _creating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check),
                        label: const Text("Créer le groupe"),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
