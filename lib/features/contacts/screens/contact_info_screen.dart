import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../models/contact.dart';
import '../../../models/message.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/motif_background.dart';
import '../../account/screens/avatar_viewer_screen.dart';
import '../../calls/call_controller.dart';
import '../../chat/chat_repository.dart';
import '../contacts_repository.dart';

/// Écran "Détails du contact" façon WhatsApp.
///
/// Sections :
///  - Photo grande + nom + numéro
///  - Statut ("À propos")
///  - Actions : Message, Appel audio, Appel vidéo
///  - Médias partagés (compte les IMAGE / VIDEO échangés dans la conv)
///  - Options : Bloquer/Débloquer, Signaler (placeholder)
///
/// [contactId] est optionnel — présent quand on ouvre depuis la liste des
/// contacts (pour permettre bloquer / débloquer / retirer). Absent quand on
/// ouvre depuis une conversation avec un utilisateur qui n'est pas dans le
/// répertoire.
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.publicNumber,
    this.avatarUrl,
    this.statusMsg,
    this.convId,
    this.contactId,
    this.isBlocked = false,
  });

  final String userId;
  final String name;
  final String publicNumber;
  final String? avatarUrl;
  final String? statusMsg;
  final String? convId;
  final String? contactId;
  final bool isBlocked;

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  late bool _isBlocked = widget.isBlocked;
  List<Message>? _sharedMedia;
  bool _loadingMedia = false;

  @override
  void initState() {
    super.initState();
    _loadSharedMedia();
  }

  Future<void> _loadSharedMedia() async {
    final convId = widget.convId;
    if (convId == null) return;
    setState(() => _loadingMedia = true);
    try {
      final msgs = await context.read<ChatRepository>().getMessages(convId);
      if (!mounted) return;
      setState(() {
        _sharedMedia = msgs
            .where((m) =>
                (m.type == "IMAGE" || m.type == "VIDEO") && m.media.isNotEmpty)
            .toList();
        _loadingMedia = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMedia = false);
    }
  }

  Future<void> _toggleBlock() async {
    final contactId = widget.contactId;
    if (contactId == null) {
      showAppSnackBar("Ajoute d'abord ce contact à ton répertoire pour le bloquer");
      return;
    }
    final newState = !_isBlocked;
    try {
      await context.read<ContactsRepository>().setBlocked(contactId, newState);
      if (!mounted) return;
      setState(() => _isBlocked = newState);
      showAppSnackBar(newState ? "Contact bloqué" : "Contact débloqué");
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar("Action impossible");
    }
  }

  void _startCall(String type) {
    final cc = context.read<CallController>();
    final convId = widget.convId;
    if (convId == null) {
      showAppSnackBar("Ouvre d'abord une conversation avec ce contact");
      return;
    }
    try {
      cc.startOutgoing(convId, type, widget.name);
    } catch (_) {
      showAppSnackBar("Impossible de lancer l'appel");
    }
  }

  void _openAvatarViewer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvatarViewerScreen(
          name: widget.name,
          avatarUrl: widget.avatarUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MotifBackground(
        overlayOpacity: 0.94,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.terracotta,
              foregroundColor: Colors.white,
              expandedHeight: 250,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(widget.name, style: const TextStyle(fontSize: 16)),
                background: GestureDetector(
                  onTap: _openAvatarViewer,
                  child: Container(
                    color: AppColors.terracotta,
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: AvatarCircle(
                        name: widget.name,
                        avatarUrl: widget.avatarUrl,
                        radius: 70,
                        backgroundColor: Colors.white24,
                        borderColor: Colors.white,
                        borderWidth: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 12),
                _actionsRow(),
                const SizedBox(height: 12),
                _aboutCard(),
                const SizedBox(height: 12),
                _numberCard(),
                const SizedBox(height: 12),
                _sharedMediaCard(),
                const SizedBox(height: 12),
                _dangerCard(),
                const SizedBox(height: 24),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.sand),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _actionButton(Icons.chat_bubble_outline, "Message", () {
            Navigator.of(context).pop(); // retour au chat si on vient de là
          }),
          _actionButton(Icons.call_outlined, "Appel", () => _startCall("AUDIO")),
          _actionButton(Icons.videocam_outlined, "Vidéo", () => _startCall("VIDEO")),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            Icon(icon, color: AppColors.forest, size: 26),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.forest)),
          ],
        ),
      ),
    );
  }

  Widget _aboutCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("À propos",
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(
            widget.statusMsg?.isNotEmpty == true
                ? widget.statusMsg!
                : "Hey ! J'utilise Alanya.",
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _numberCard() {
    return _card(
      child: Row(
        children: [
          const Icon(Icons.tag, color: AppColors.terracotta),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Numéro Alanya",
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text(
                  _formatNumber(widget.publicNumber),
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Copier",
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.publicNumber));
              showAppSnackBar("Numéro copié");
            },
          ),
        ],
      ),
    );
  }

  String _formatNumber(String n) {
    // Format 2 par 2 pour lisibilité : "67641599" → "67 64 15 99"
    final buf = StringBuffer();
    for (int i = 0; i < n.length; i++) {
      if (i > 0 && i % 2 == 0) buf.write(' ');
      buf.write(n[i]);
    }
    return buf.toString();
  }

  Widget _sharedMediaCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.perm_media_outlined, color: AppColors.forest),
              const SizedBox(width: 10),
              const Expanded(
                child: Text("Médias, liens et docs",
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (_loadingMedia)
                const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text("${_sharedMedia?.length ?? 0}",
                    style: const TextStyle(color: Colors.black54)),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
          if (_sharedMedia != null && _sharedMedia!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text("Aucun média partagé",
                  style: TextStyle(color: Colors.black54, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _dangerCard() {
    return _card(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _isBlocked ? Icons.lock_open : Icons.block,
              color: Colors.red,
            ),
            title: Text(
              _isBlocked ? "Débloquer ${widget.name}" : "Bloquer ${widget.name}",
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
            onTap: _toggleBlock,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title: const Text(
              "Signaler",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
            onTap: () => showAppSnackBar("Signalement bientôt disponible"),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.sand),
      ),
      child: child,
    );
  }
}
