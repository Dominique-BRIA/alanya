import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../auth/auth_controller.dart';
import '../../chat/chat_repository.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../chat/screens/chat_screen.dart';

/// Écran d'infos d'un groupe — style WhatsApp.
///
/// Affiche : nom, avatar, membres, actions (ajouter, retirer, quitter, modifier).
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.convId,
    required this.title,
    required this.avatarUrl,
    required this.members,
  });

  final String convId;
  final String title;
  final String? avatarUrl;
  final List<Map<String, dynamic>> members; // [{id, pseudo, publicNumber, avatarUrl, isOnline, role}]

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late List<Map<String, dynamic>> _members;
  late String _title;
  late String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _members = List.from(widget.members);
    _title = widget.title;
    _avatarUrl = widget.avatarUrl;
  }

  String get _myId => context.read<AuthController>().user?.id ?? '';

  /// Vérifie si l'utilisateur connecté est admin dans CE groupe.
  bool get _amAdmin {
    final me = _members.firstWhere(
      (m) => m['id'] == _myId,
      orElse: () => {},
    );
    return (me['role'] as String?) == 'ADMIN';
  }

  Future<void> _refreshMembers() async {
    try {
      final data = await context.read<ChatRepository>().getGroupMembers(widget.convId);
      if (mounted) setState(() => _members = data);
    } catch (_) {}
  }

  // ===================== MODIFIER LE NOM =====================

  Future<void> _editName() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seul un admin peut modifier le nom du groupe")),
      );
      return;
    }
    final ctrl = TextEditingController(text: _title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nom du groupe"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: "Entrez le nom du groupe"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text("Enregistrer")),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != _title) {
      try {
        await context.read<ChatRepository>().updateGroup(widget.convId, name: newName);
        setState(() => _title = newName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Nom du groupe mis à jour")),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Erreur lors de la mise à jour")),
          );
        }
      }
    }
  }

  // ===================== MODIFIER L'AVATAR =====================

  Future<void> _editAvatar() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seul un admin peut modifier l'avatar du groupe")),
      );
      return;
    }
    final ctrl = TextEditingController(text: _avatarUrl ?? '');
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Photo du groupe"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Aperçu actuel
            if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AvatarCircle(
                  name: _title,
                  avatarUrl: _avatarUrl,
                  radius: 40,
                  backgroundColor: AlanyaColors.forest,
                ),
              ),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: "URL de l'image",
                prefixIcon: Icon(Icons.link),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text("Enregistrer")),
        ],
      ),
    );
    if (newUrl != null) {
      try {
        await context.read<ChatRepository>().updateGroup(widget.convId, avatarUrl: newUrl);
        setState(() => _avatarUrl = newUrl.isEmpty ? null : newUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Photo du groupe mise à jour")),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Erreur lors de la mise à jour")),
          );
        }
      }
    }
  }

  // ===================== AJOUTER DES MEMBRES =====================

  Future<void> _addMembers() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seul un admin peut ajouter des membres")),
      );
      return;
    }
    final existingNumbers = _members
        .map((m) => (m['publicNumber'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final result = await ContactPickerSheet.show(
      context,
      title: "Ajouter des membres",
      confirmLabel: "Ajouter",
      excludeNumbers: existingNumbers,
    );
    if (result != null && result.isNotEmpty) {
      try {
        await context.read<ChatRepository>().addMembersToGroup(widget.convId, result);
        await _refreshMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${result.length} membre(s) ajouté(s)")),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = (e is ApiException) ? e.message : "Erreur lors de l'ajout";
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }
  }

  // ===================== RETIRER UN MEMBRE =====================

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final name = member['pseudo'] ?? member['publicNumber'] ?? 'Membre';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Retirer $name ?"),
        content: Text("$name sera retiré du groupe."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Retirer", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await context.read<ChatRepository>().removeMemberFromGroup(
              widget.convId,
              member['id'] as String,
            );
        await _refreshMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("$name retiré du groupe")),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = (e is ApiException) ? e.message : "Erreur lors du retrait";
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }
  }

  // ===================== QUITTER LE GROUPE =====================

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Quitter le groupe ?"),
        content: const Text(
            "Vous ne recevrez plus de messages de ce groupe. Vous pouvez être réinvité plus tard."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Quitter", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await context.read<ChatRepository>().leaveGroup(widget.convId);
        if (mounted) {
          Navigator.of(context).pop(); // retour à la liste
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Vous avez quitté le groupe")),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Erreur lors de la sortie")),
          );
        }
      }
    }
  }

  // ===================== ENVOYER UN MESSAGE (DM) =====================

  Future<void> _sendMessageTo(Map<String, dynamic> member) async {
    final targetId = member['id'] as String;
    final name = member['pseudo'] ?? member['publicNumber'] ?? 'Membre';
    final avatarUrl = member['avatarUrl'] as String?;

    try {
      // Cherche ou crée une conversation 1-to-1 avec ce membre
      final convData = await context.read<ChatRepository>().getOrCreateDirectConversation(targetId);
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convData['id'] as String,
            title: name,
            avatarUrl: avatarUrl,
            isGroup: false,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir la conversation")),
        );
      }
    }
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Infos du groupe"),
      body: ListView(
        children: [
          // ====== EN-TÊTE : AVATAR + NOM ======
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _amAdmin ? _editAvatar : null,
                  child: Stack(
                    children: [
                      AvatarCircle(
                        name: _title,
                        avatarUrl: _avatarUrl,
                        radius: 40,
                        backgroundColor: AlanyaColors.forest,
                      ),
                      if (_amAdmin)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AlanyaColors.terracotta,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(_title,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                    if (_amAdmin)
                      IconButton(
                        icon: Icon(Icons.edit, size: 20, color: AlanyaColors.grey500),
                        onPressed: _editName,
                      ),
                  ],
                ),
                Text("${_members.length} membres",
                    style: TextStyle(color: AlanyaColors.grey500)),
              ],
            ),
          ),

          // ====== ACTIONS ======
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AlanyaColors.grey200, width: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_amAdmin)
                  _actionButton(Icons.person_add, "Ajouter", _addMembers),
                _actionButton(Icons.exit_to_app, "Quitter", _leaveGroup,
                    color: Colors.red),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ====== LISTE DES MEMBRES ======
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text("Membres",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AlanyaColors.grey500)),
          ),
          const SizedBox(height: 8),

          ..._members.map((m) {
            final isMe = m['id'] == _myId;
            final name = m['pseudo'] ?? m['publicNumber'] ?? 'Membre';
            final online = (m['isOnline'] as int?) == 1;
            final isAdmin = (m['role'] as String?) == 'ADMIN';

            return ListTile(
              leading: AvatarCircle(
                name: name,
                avatarUrl: m['avatarUrl'] as String?,
                radius: 20,
                backgroundColor: isMe ? AlanyaColors.terracotta : AlanyaColors.gold,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  if (isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AlanyaColors.terracotta.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text("Admin",
                          style: TextStyle(
                              fontSize: 10,
                              color: AlanyaColors.terracotta,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              subtitle: Text(
                online
                    ? "en ligne"
                    : (m['publicNumber'] as String? ?? ''),
                style: TextStyle(
                    fontSize: 12,
                    color: online ? AlanyaColors.forest : AlanyaColors.grey500),
              ),
              trailing: (!isMe)
                  ? IconButton(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onPressed: () => _showMemberOptions(m),
                    )
                  : null,
            );
          }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color ?? AlanyaColors.forest, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color ?? AlanyaColors.forest,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _showMemberOptions(Map<String, dynamic> member) {
    final name = member['pseudo'] ?? member['publicNumber'] ?? 'Membre';
    final isMe = member['id'] == _myId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            if (!isMe) ...[
              ListTile(
                leading: const Icon(Icons.message, color: AlanyaColors.forest),
                title: const Text("Envoyer un message"),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendMessageTo(member);
                },
              ),
              if (_amAdmin)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  title: const Text("Retirer du groupe",
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeMember(member);
                  },
                ),
            ],
            if (isMe)
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text("Quitter le groupe",
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _leaveGroup();
                },
              ),
          ],
        ),
      ),
    );
  }
}
