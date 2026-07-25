import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/token_storage.dart';
import '../../../models/message.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/media/cached_media.dart';
import '../../account/screens/avatar_viewer_screen.dart';
import '../../calls/call_controller.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/shared_content_screen.dart';
import '../contacts_repository.dart';

/// Écran "Info Contact" — design premium glassmorphism, mode sombre prioritaire.
///
/// Sections :
///  - Header collapsible (dégradé + glass, avatar qui se réduit au scroll,
///    nom, statut en ligne / dernière connexion)
///  - Actions rapides : Appeler, Message, Vidéo (boutons ronds)
///  - Informations : numéro, bio, username (optionnel) — cartes glass
///  - Médias partagés : liste horizontale de miniatures arrondies
///  - Paramètres : sourdine (locale) + bloquer le contact
///
/// [contactId] est optionnel — présent quand on ouvre depuis la liste des
/// contacts (requis pour bloquer). [isOnline]/[lastSeen] alimentent le statut
/// (snapshot, pas de présence temps réel). [username] est optionnel.
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.publicNumber,
    this.avatarUrl,
    this.statusMsg,
    this.username,
    this.convId,
    this.contactId,
    this.isBlocked = false,
    this.isOnline = false,
    this.lastSeen,
  });

  final String userId;
  final String name;
  final String publicNumber;
  final String? avatarUrl;
  final String? statusMsg;
  final String? username;
  final String? convId;
  final String? contactId;
  final bool isBlocked;
  final bool isOnline;
  final DateTime? lastSeen;

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  static const double _expandedHeight = 300;

  late bool _isBlocked = widget.isBlocked;
  List<Message>? _sharedMedia;
  bool _loadingMedia = false;
  String _baseUrl = "";
  String? _token;

  bool _muted = false;

  String get _muteKey => "mute_${widget.convId ?? widget.userId}";

  @override
  void initState() {
    super.initState();
    _loadMuted();
    _loadSharedMedia();
  }

  Future<void> _loadMuted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => _muted = prefs.getBool(_muteKey) ?? false);
    } catch (_) {}
  }

  Future<void> _toggleMuted(bool value) async {
    setState(() => _muted = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_muteKey, value);
    } catch (_) {}
    showAppSnackBar(
        value ? "Notifications en sourdine" : "Notifications réactivées");
  }

  Future<void> _loadSharedMedia() async {
    final convId = widget.convId;
    if (convId == null) return;
    setState(() => _loadingMedia = true);
    _baseUrl = context.read<ApiClient>().baseUrl;
    _token = await context.read<TokenStorage>().accessToken;
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
      showAppSnackBar(
          "Ajoute d'abord ce contact à ton répertoire pour le bloquer");
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

  void _openMessage() {
    // La fiche est ouverte depuis le chat → revenir affiche la conversation.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      showAppSnackBar("Ouvre la conversation depuis l'accueil");
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

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          _buildHeader(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                children: [
                  _actionsRow(),
                  const SizedBox(height: 18),
                  _infoCard(),
                  const SizedBox(height: 16),
                  _sharedMediaCard(),
                  const SizedBox(height: 16),
                  _settingsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER collapsible (dégradé + glass, avatar qui se réduit au scroll)
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.of(context).padding.top;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const [Color(0xFF3A2A20), AlanyaColors.forestDark]
          : const [AlanyaColors.terracotta, AlanyaColors.forest],
    );

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: _expandedHeight,
      backgroundColor:
          dark ? const Color(0xFF2A1E17) : AlanyaColors.terracottaDark,
      foregroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = _expandedHeight + topPad;
          final minH = kToolbarHeight + topPad;
          final h = constraints.maxHeight;
          // t = 1 (déployé) → 0 (replié).
          final t = ((h - minH) / (maxH - minH)).clamp(0.0, 1.0);
          final avatarRadius = 34 + 24 * t; // 34 → 58
          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
              // Voile sombre en bas pour la lisibilité du texte.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black26],
                  ),
                ),
              ),
              // Titre replié (apparaît quand le header se réduit).
              Positioned(
                top: topPad,
                left: 56,
                right: 56,
                height: kToolbarHeight,
                child: Opacity(
                  opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Opacity(
                  opacity: (t * 1.4 - 0.15).clamp(0.0, 1.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _openAvatarViewer,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: AvatarCircle(
                            name: widget.name,
                            avatarUrl: widget.avatarUrl,
                            radius: avatarRadius,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          widget.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _presenceLine(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _presenceLine() {
    final label = _presenceLabel();
    if (label == null) return const SizedBox.shrink();
    final online = widget.isOnline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (online) ...[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AlanyaColors.forestLight,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ],
    );
  }

  String? _presenceLabel() {
    if (widget.isOnline) return "en ligne";
    final ls = widget.lastSeen;
    if (ls == null) return null;
    final diff = DateTime.now().difference(ls);
    if (diff.inMinutes < 1) return "vu à l'instant";
    if (diff.inMinutes < 60) return "vu il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "vu il y a ${diff.inHours} h";
    return "vu il y a ${diff.inDays} j";
  }

  // ---------------------------------------------------------------------------
  // ACTIONS RAPIDES
  // ---------------------------------------------------------------------------
  Widget _actionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundAction(
          icon: Icons.call_rounded,
          label: "Appeler",
          onTap: () => _startCall("AUDIO"),
        ),
        _RoundAction(
          icon: Icons.chat_bubble_rounded,
          label: "Message",
          onTap: _openMessage,
        ),
        _RoundAction(
          icon: Icons.videocam_rounded,
          label: "Vidéo",
          onTap: () => _startCall("VIDEO"),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // INFORMATIONS
  // ---------------------------------------------------------------------------
  Widget _infoCard() {
    final bio = widget.statusMsg?.isNotEmpty == true
        ? widget.statusMsg!
        : "Hey ! J'utilise Alanya.";
    final username = widget.username;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: [
          _infoRow(
            icon: Icons.phone_rounded,
            label: "Téléphone",
            value: "#${_formatNumber(widget.publicNumber)}",
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.publicNumber));
              showAppSnackBar("Numéro copié");
            },
            trailing: Icons.copy_rounded,
          ),
          _divider(),
          _infoRow(
            icon: Icons.info_outline_rounded,
            label: "À propos",
            value: bio,
          ),
          if (username != null && username.isNotEmpty) ...[
            _divider(),
            _infoRow(
              icon: Icons.alternate_email_rounded,
              label: "Nom d'utilisateur",
              value: username,
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    IconData? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: AlanyaColors.terracotta),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Icon(trailing, size: 18, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 48,
      endIndent: 12,
      color: cs.onSurface.withValues(alpha: 0.08),
    );
  }

  // ---------------------------------------------------------------------------
  // MÉDIAS PARTAGÉS
  // ---------------------------------------------------------------------------
  Widget _sharedMediaCard() {
    final cs = Theme.of(context).colorScheme;
    final hasConv = widget.convId != null;
    final recent = (_sharedMedia ?? const <Message>[]).take(8).toList();
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: hasConv
          ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SharedContentScreen(
                    convId: widget.convId!, title: widget.name),
              ))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.perm_media_rounded,
                  size: 20, color: AlanyaColors.terracotta),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Médias partagés",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (_loadingMedia)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text("${_sharedMedia?.length ?? 0}",
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
          if (recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final m = recent[i];
                    final media = m.media.first;
                    final isVideo = m.type == "VIDEO";
                    final url = '$_baseUrl${media.url}?token=$_token';
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: isVideo
                            ? const ColoredBox(
                                color: Color(0xFF1A1A2E),
                                child: Icon(Icons.play_circle_fill_rounded,
                                    color: Colors.white70, size: 30),
                              )
                            : CachedMedia(
                                url: url,
                                width: 76,
                                height: 76,
                                fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_sharedMedia != null && _sharedMedia!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text("Aucun média partagé",
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PARAMÈTRES
  // ---------------------------------------------------------------------------
  Widget _settingsCard() {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            secondary: Icon(
              _muted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_rounded,
              color: AlanyaColors.terracotta,
            ),
            title: Text(
              "Notifications",
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface),
            ),
            subtitle: Text(
              _muted ? "En sourdine" : "Activées",
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            value: !_muted,
            activeColor: AlanyaColors.forest,
            onChanged: (on) => _toggleMuted(!on),
          ),
          _divider(),
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              leading: Icon(
                _isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                color: AlanyaColors.error,
              ),
              title: Text(
                _isBlocked
                    ? "Débloquer ${widget.name}"
                    : "Bloquer ${widget.name}",
                style: const TextStyle(
                    color: AlanyaColors.error,
                    fontWeight: FontWeight.w500,
                    fontSize: 15),
              ),
              onTap: _toggleBlock,
            ),
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
}

/// Bouton d'action rond avec icône + label (micro-interaction au tap).
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AlanyaColors.terracotta.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 60,
              height: 60,
              child: Icon(icon, color: AlanyaColors.terracotta, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
