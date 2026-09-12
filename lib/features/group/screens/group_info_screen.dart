import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../media/media_repository.dart';
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
import '../../../l10n/app_localizations.dart';

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
    _refreshMembers();
  }

  String get _myId => context.read<AuthController>().user?.id ?? '';

  /// Vérifie si l'utilisateur connecté est admin dans CE groupe.
  bool get _amAdmin {
    if (_members.isEmpty) return false;
    final me = _members.firstWhere(
      (m) => m['id'] == _myId,
      orElse: () => {},
    );
    if ((me['role'] as String?) == 'ADMIN') return true;
    final hasAnyAdmin = _members.any((m) => (m['role'] as String?) == 'ADMIN');
    if (!hasAnyAdmin && _members.first['id'] == _myId) return true;
    return false;
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
        SnackBar(content: Text(tr(context, 'grp_admin_only_name'))),
      );
      return;
    }
    final ctrl = TextEditingController(text: _title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'grp_name_label')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: tr(ctx, 'grp_name_hint')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(tr(ctx, 'save'))),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != _title) {
      try {
        await context.read<ChatRepository>().updateGroup(widget.convId, name: newName);
        setState(() => _title = newName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_name_updated'))),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_update_failed'))),
          );
        }
      }
    }
  }

  // ===================== MODIFIER L'AVATAR =====================

  Future<void> _editAvatar() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'grp_admin_only_avatar'))),
      );
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'gallery_open_failed'))),
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'image_too_large'))),
        );
      }
      return;
    }

    try {
      final mediaRepo = context.read<MediaRepository>();
      final mime = _mimeFromBytes(bytes) ?? _mimeFromName(file.name);
      final uploaded = await mediaRepo.upload(bytes, file.name, mime);

      await context.read<ChatRepository>().updateGroup(widget.convId, avatarUrl: uploaded.url);
      setState(() => _avatarUrl = uploaded.url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'grp_avatar_updated'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'grp_avatar_failed'))),
        );
      }
    }
  }

  String? _mimeFromBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return "image/jpeg";
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return "image/png";
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return "image/gif";
    return "image/jpeg";
  }

  String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith(".png")) return "image/png";
    if (n.endsWith(".webp")) return "image/webp";
    if (n.endsWith(".gif")) return "image/gif";
    return "image/jpeg";
  }

  // ===================== AJOUTER DES MEMBRES =====================

  Future<void> _addMembers() async {
    if (!_amAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'grp_admin_only_add'))),
      );
      return;
    }
    final existingNumbers = _members
        .map((m) => (m['publicNumber'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final result = await ContactPickerSheet.show(
      context,
      title: tr(context, 'grp_add_members'),
      confirmLabel: tr(context, 'add'),
      excludeNumbers: existingNumbers,
    );
    if (result != null && result.isNotEmpty) {
      try {
        await context.read<ChatRepository>().addMembersToGroup(widget.convId, result);
        await _refreshMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(trN(context, 'grp_members_added', result.length))),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = (e is ApiException) ? e.message : tr(context, 'grp_add_failed');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }
  }

  // ===================== RETIRER UN MEMBRE =====================

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'grp_remove_q', {'nom': name})),
        content: Text(tr(context, 'grp_remove_body', {'nom': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, 'remove'), style: TextStyle(color: dangerOf(context)))),
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
            SnackBar(content: Text(tr(context, 'grp_member_removed', {'nom': name}))),
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

  Future<void> _changeMemberRole(Map<String, dynamic> member, String role) async {
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
    try {
      await context
          .read<ChatRepository>()
          .changeMemberRole(widget.convId, member['id'] as String, role);
      await _refreshMembers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(role == 'ADMIN'
                ? "$name est maintenant administrateur"
                : "$name n'est plus administrateur"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg =
            (e is ApiException) ? e.message : "Erreur lors du changement de rôle";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // ===================== QUITTER LE GROUPE =====================

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'grp_leave_q')),
        content: Text(
            tr(context, 'grp_leave_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, 'leave_action'), style: TextStyle(color: dangerOf(context)))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await context.read<ChatRepository>().leaveGroup(widget.convId);
        if (mounted) {
          Navigator.of(context).pop(); // retour à la liste
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_left'))),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'grp_leave_failed'))),
          );
        }
      }
    }
  }

  // ===================== ENVOYER UN MESSAGE (DM) =====================

  Future<void> _sendMessageTo(Map<String, dynamic> member) async {
    final targetId = member['id'] as String;
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
    final avatarUrl = member['avatarUrl'] as String?;

    try {
      // Cherche ou crée une conversation 1-to-1 avec ce membre
      final convData = await context.read<ChatRepository>().getOrCreateDirectConversation(targetId);
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convData['id'] as String,
            title: name,
            avatarUrl: avatarUrl,
            isGroup: false,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'chat_open_failed'))),
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
                        backgroundColor: positiveOf(context),
                      ),
                      if (_amAdmin)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: accentOf(context),
                              shape: BoxShape.circle,
                              border: Border.all(color: themed(context, light: Colors.white, dark: surfacesOf(context).fond), width: 2),
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
                        icon: Icon(Icons.edit, size: 20, color: mutedOf(context, AlanyaColors.grey500)),
                        onPressed: _editName,
                      ),
                  ],
                ),
                Text(trN(context, 'grp_members', _members.length),
                    style: TextStyle(color: mutedOf(context, AlanyaColors.grey500))),
              ],
            ),
          ),

          // ====== ACTIONS ======
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: themed(context, light: Colors.white, dark: surfacesOf(context).surface),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne), width: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(Icons.person_add, "Ajouter", _addMembers),
                _actionButton(Icons.exit_to_app, "Quitter", _leaveGroup,
                    color: dangerOf(context)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ====== LISTE DES MEMBRES ======
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(tr(context, 'members_label'),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: mutedOf(context, AlanyaColors.grey500))),
          ),
          const SizedBox(height: 8),

          ..._members.map((m) {
            final isMe = m['id'] == _myId;
            final name = m['pseudo'] ?? m['publicNumber'] ?? tr(context, 'grp_member');
            final online = (m['isOnline'] as int?) == 1;
            final isAdmin = (m['role'] as String?) == 'ADMIN';

            return ListTile(
              leading: AvatarCircle(
                name: name,
                avatarUrl: m['avatarUrl'] as String?,
                radius: 20,
                backgroundColor: isMe ? accentOf(context) : AlanyaColors.gold,
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
                        color: accentOf(context).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tr(context, 'grp_admin'),
                          style: TextStyle(
                              fontSize: 10,
                              color: accentOf(context),
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
                    color: online ? positiveOf(context) : mutedOf(context, AlanyaColors.grey500)),
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
            Icon(icon, color: color ?? positiveOf(context), size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color ?? positiveOf(context),
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _showMemberOptions(Map<String, dynamic> member) {
    final name = member['pseudo'] ?? member['publicNumber'] ?? tr(context, 'grp_member');
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
                leading: Icon(Icons.message, color: positiveOf(context)),
                title: Text(tr(context, 'send_message_action')),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendMessageTo(member);
                },
              ),
              if (_amAdmin) ...[
                if ((member['role'] as String?) == 'ADMIN')
                  ListTile(
                    leading: Icon(Icons.remove_moderator_outlined,
                        color: themed(context, light: AlanyaColors.chocolate, dark: AlanyaColors.craie2)),
                    title: Text(tr(context, 'remove_admin')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeMemberRole(member, 'MEMBER');
                    },
                  )
                else
                  ListTile(
                    leading: Icon(Icons.shield_outlined,
                        color: positiveOf(context)),
                    title: Text(tr(context, 'make_admin')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeMemberRole(member, 'ADMIN');
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.remove_circle_outline, color: dangerOf(context)),
                  title: Text(tr(context, 'remove_from_group'),
                      style: TextStyle(color: dangerOf(context))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeMember(member);
                  },
                ),
              ],
            ],
            if (isMe)
              ListTile(
                leading: Icon(Icons.exit_to_app, color: dangerOf(context)),
                title: Text(tr(context, 'grp_leave_action'),
                    style: TextStyle(color: dangerOf(context))),
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
