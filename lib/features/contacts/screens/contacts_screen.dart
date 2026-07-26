import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/contact_cache.dart';
import '../../../models/contact.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/chat_screen.dart';
import '../../chat/screens/new_group_screen.dart';
import '../contacts_repository.dart';
import 'new_chat_screen.dart';
import 'phone_sync_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact>? _contacts;
  bool _loading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    // 1) Cache local d'abord (offline-first).
    final cached = await ContactCache.getAll();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _contacts = cached;
        _loading = false;
        _errorMsg = null;
      });
    }

    // 2) Rafraîchit depuis le serveur.
    try {
      final list = await context.read<ContactsRepository>().list();
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
        _errorMsg = null;
      });
      await ContactCache.putAll(list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Ne montre l'erreur que si le cache était vide (aucun contenu à afficher).
        _errorMsg = (_contacts?.isEmpty ?? true)
            ? "Erreur ${e.statusCode} : ${e.message}"
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = (_contacts?.isEmpty ?? true)
            ? "Impossible de charger les contacts.\nVérifie ta connexion."
            : null;
      });
    }
  }

  Future<void> _startChat(Contact c) async {
    final chat = context.read<ChatRepository>();
    try {
      final convId = await chat.createDirect(c.publicNumber);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title: c.displayName,
            avatarUrl: c.avatarUrl,
            otherUserId: c.userId,
            otherPublicNumber: c.publicNumber,
            contactId: c.id,
            isBlocked: c.isBlocked,
          ),
        ),
      );
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Impossible d'ouvrir la discussion");
    }
  }

  Future<void> _toggleBlock(Contact c) async {
    try {
      await context.read<ContactsRepository>().setBlocked(c.id, !c.isBlocked);
      await _load();
    } catch (_) {
      _snack("Action impossible");
    }
  }

  Future<void> _remove(Contact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Supprimer le contact ?"),
        content: Text("${c.displayName} sera retiré de ton répertoire."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Supprimer")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<ContactsRepository>().remove(c.id);
      await _load();
    } catch (_) {
      _snack("Suppression impossible");
    }
  }

  void _snack(String m) => showAppSnackBar(m);


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(
        context,
        "Contacts",
        actions: [
          // Synchronisation depuis le répertoire téléphonique
          IconButton(
            tooltip: "Importer depuis le téléphone",
            icon: const Icon(Icons.contacts_outlined),
            onPressed: () async {
              final added = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const PhoneSyncScreen()),
              );
              if (added == true) _load();
            },
          ),
          // Bouton actualiser toujours visible
          IconButton(
            tooltip: "Actualiser",
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: RefreshIndicator(onRefresh: _load, child: _body()),
      ),
    );
  }

  Widget _body() {
    // Chargement initial
    if (_contacts == null && _loading) {
      return Center(child: CircularProgressIndicator(color: accentOf(context)));
    }

    // Erreur avec bouton retry
    if (_errorMsg != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.cloud_off, size: 48, color: faintOf(context, Colors.black26)),
                  const SizedBox(height: 12),
                  Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedOf(context, Colors.black54)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text("Réessayer"),
                    style: ElevatedButton.styleFrom(backgroundColor: accentOf(context)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final contacts = _contacts ?? [];
    if (contacts.isEmpty) {
      return ListView(
        children: [
          // --- Actions rapides (visibles même si aucun contact) ---
          _actionTile(
            icon: Icons.group_add,
            color: themed(context, light: AlanyaColors.forest, dark: AlanyaColors.indigoLight),
            title: "Nouveau groupe",
            subtitle: "Créer un groupe avec des contacts",
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewGroupScreen()),
              );
              _load();
            },
          ),
          const Divider(height: 1),
          _actionTile(
            icon: Icons.person_add,
            color: accentOf(context),
            title: "Ajouter un contact",
            subtitle: "Rechercher par Alanya ID",
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewChatScreen()),
              );
              _load();
            },
          ),

          Divider(height: 1, thickness: 8, color: themed(context, light: AlanyaColors.cream, dark: AlanyaColors.nuit)),
          // --- Message d'état vide ---
          const SizedBox(height: 60),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.people_outline,
                      size: 56, color: faintOf(context, Colors.black12)),
                  const SizedBox(height: 12),
                  Text(
                    "Aucun contact pour l'instant.\nUtilise les options ci-dessus pour en ajouter.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedOf(context, Colors.black54)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        ListView(
          children: [
            // --- Actions rapides (style WhatsApp) ---
            _actionTile(
              icon: Icons.group_add,
              color: themed(context, light: AlanyaColors.forest, dark: AlanyaColors.indigoLight),
              title: "Nouveau groupe",
              subtitle: "Créer un groupe avec des contacts",
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewGroupScreen()),
                );
                _load();
              },
            ),
            const Divider(height: 1),
            _actionTile(
              icon: Icons.person_add,
              color: accentOf(context),
              title: "Ajouter un contact",
              subtitle: "Rechercher par Alanya ID",
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewChatScreen()),
                );
                _load();
              },
            ),

            Divider(height: 1, thickness: 8, color: themed(context, light: AlanyaColors.cream, dark: AlanyaColors.nuit)),
            // --- Liste des contacts ---
            ...contacts.map((c) => _tile(c)),
          ],
        ),
        if (_loading)
          Positioned(
            top: 0, left: 0, right: 0,
            child: LinearProgressIndicator(color: accentOf(context)),
          ),
      ],
    );
  }

  /// Tuile d'action rapide (style WhatsApp) placée au-dessus de la liste.
  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      onTap: onTap,
    );
  }

  Widget _tile(Contact c) {
    return ListTile(
      leading: AvatarCircle(
        name: c.displayName,
        avatarUrl: c.avatarUrl,
        radius: 22,
        backgroundColor: c.isBlocked ? themed(context, light: Colors.grey, dark: AlanyaColors.nuit3) : AlanyaColors.gold,
      ),
      title: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text("Numéro : ${c.publicNumber}${c.isBlocked ? " · bloqué" : ""}"),
      onTap: c.isBlocked ? null : () => _startChat(c),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == "chat") _startChat(c);
          if (v == "block") _toggleBlock(c);
          if (v == "delete") _remove(c);
        },
        itemBuilder: (_) => [
          if (!c.isBlocked)
            const PopupMenuItem(value: "chat", child: Text("Discuter")),
          PopupMenuItem(value: "block", child: Text(c.isBlocked ? "Débloquer" : "Bloquer")),
          const PopupMenuItem(value: "delete", child: Text("Supprimer")),
        ],
      ),
    );
  }
}
