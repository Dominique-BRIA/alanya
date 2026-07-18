import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';

import '../../core/connectivity_service.dart';
import '../../core/conversation_cache.dart';
import '../../core/push_service.dart';
import '../../core/realtime_client.dart';
import '../../models/ai_message.dart';
import '../../models/conversation.dart';
import '../../models/status.dart';
import '../../theme/alanya_theme.dart';
import '../../widgets/alanya_nav_bar.dart';
import '../../widgets/avatar_circle.dart';
import '../../widgets/motif_background.dart';
import '../../widgets/multi_select_mixin.dart';
import '../account/screens/avatar_viewer_screen.dart';
import '../account/screens/profile_screen.dart';
import '../ai/ai_repository.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_repository.dart';
import '../chat/screens/chat_screen.dart';
import '../contacts/screens/contacts_screen.dart';
import '../chat/screens/new_group_screen.dart';
import '../contacts/screens/add_contact_screen.dart';
import '../contacts/screens/new_chat_screen.dart';
import '../calls/call_controller.dart';
import '../calls/call_listener.dart';
import '../calls/screens/calls_screen.dart';
import '../meetings/screens/meetings_screen.dart';
import '../status/screens/create_status_screen.dart';
import '../status/screens/status_viewer_screen.dart';
import '../status/status_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Ouvre la connexion temps réel dès que l'utilisateur est sur l'accueil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RealtimeClient>().connect();
      final user = context.read<AuthController>().user;
      if (user != null) {
        context.read<CallController>().bindUser(
              user.id,
              user.pseudo ?? user.publicNumber,
            );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    // FIX: NE PAS déconnecter la WS ici.
    // HomeScreen peut être démonté/remonté (changement de langue via
    // LocaleController.notifyListeners, rotation, hot restart, etc.).
    // Si on disconnect ici, la WS coupe pendant plusieurs secondes et
    // toute trame `incoming_call` reçue pendant ce trou est PERDUE côté
    // serveur (sendTo ne bufferise pas les users offline).
    // La WS doit vivre tant que l'utilisateur est loggué. Elle sera fermée
    // par AuthController.logout() ou par RealtimeClient.dispose() en fin
    // de vie de l'app.
    super.dispose();
  }

  void _openNewConversationMenu() {
    // Les options ont été déplacées vers l'écran Contacts (style WhatsApp).
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const _ConversationsTab(),
      const _StatusTab(),
      const CallsScreen(),
      const MeetingsScreen(),
      const _AiTab(),
    ];

    return Scaffold(
      appBar: AppBar(
          title: const Text(
            "ALANYA",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              height: 1,
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == "profile") {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                } else if (v == "archived") {
                  _showArchived();
                } else if (v == "logout") {
                  context.read<AuthController>().logout();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: "profile", child: Text("Mon profil")),
                const PopupMenuItem(
                  value: "archived",
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title: Text("Conversations archivées"),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(value: "logout", child: Text("Se déconnecter")),
              ],
            ),
          ],
        ),
        body: IndexedStack(index: _tab, children: tabs),
        floatingActionButton: _tab == 0
            ? FloatingActionButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ContactsScreen()),
                ),
                child: const Icon(Icons.edit, color: Colors.white),
              )
            : null,
        bottomNavigationBar: AlanyaNavBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          items: const [
            AlanyaNavItem(
              icon: Icons.chat_bubble_outline,
              activeIcon: Icons.chat_bubble,
              label: 'Chats',
            ),
            AlanyaNavItem(
              icon: Icons.radio_button_unchecked,
              activeIcon: Icons.adjust,
              label: 'Status',
            ),
            AlanyaNavItem(
              icon: Icons.call_outlined,
              activeIcon: Icons.call,
              label: 'Appels',
            ),
            AlanyaNavItem(
              icon: Icons.videocam_outlined,
              activeIcon: Icons.videocam,
              label: 'Réunions',
            ),
            AlanyaNavItem(
              icon: Icons.auto_awesome_outlined,
              activeIcon: Icons.auto_awesome,
              label: 'IA',
            ),
          ],
        ),
    );
  }
}

class _ConversationsTab extends StatefulWidget {
  const _ConversationsTab();

  @override
  State<_ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<_ConversationsTab>
    with MultiSelectMixin<_ConversationsTab> {
  List<Conversation>? _convs;
  bool _error = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Rafraîchit la liste + affiche une notification locale pour les nouveaux messages.
    _rtSub = context.read<RealtimeClient>().events.listen((e) {
      final t = e["type"];
      if (t == "message") {
        _poll();
        // Notification locale si l'utilisateur n'est PAS dans cette conversation
        final msg = e["message"] as Map<String, dynamic>?;
        final convId = msg?["convId"] as String?;
        final senderId = msg?["senderId"] as String?;
        final myId = context.read<AuthController>().user?.id;
        // Ne pas notifier si c'est mon propre message OU si je suis dans cette conv
        if (senderId != myId && convId != null && convId != ChatScreen.activeConvId) {
          _showMessageNotification(e);
        }
      } else if (t == "read") {
        _poll();
      }
    });
    // Rafraîchissement de repli (dernier message, non-lus) si le WS est coupé.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  /// Affiche une notification locale pour un message entrant.
  void _showMessageNotification(Map<String, dynamic> e) {
    final msg = e["message"] as Map<String, dynamic>?;
    if (msg == null) return;

    final convId = msg["convId"] as String? ?? "";
    final content = msg["content"] as String?;
    final type = msg["type"] as String? ?? "TEXT";

    // Trouve le titre de la conversation (expéditeur)
    String title = "Nouveau message";
    for (final c in _convs ?? <Conversation>[]) {
      if (c.id == convId) {
        title = c.title ?? "Discussion";
        break;
      }
    }

    // Aperçu du message selon le type
    String body;
    switch (type) {
      case "IMAGE":
        body = "Photo";
        break;
      case "AUDIO":
        body = "Message vocal";
        break;
      case "FILE":
        body = "Fichier";
        break;
      case "VIDEO":
        body = "Vidéo";
        break;
      default:
        body = content ?? "Nouveau message";
    }

    // Affiche la notification locale
    PushService.instance.show(
      title: title,
      body: body,
      id: convId.hashCode,
      payload: {"type": "message", "convId": convId},
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _rtSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 1) Charge d'abord le cache local (affichage instantané, offline-first).
    final cached = await ConversationCache.getAll();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _convs = cached;
        _error = false;
      });
    }

    // 2) Synchronise avec le serveur en arrière-plan.
    try {
      final convs = await context.read<ChatRepository>().listConversations();
      if (!mounted) return;
      setState(() {
        _convs = convs;
        _error = false;
      });
      // Met à jour le cache pour la prochaine fois.
      await ConversationCache.putAll(convs);
      // Signale à l'app qu'on est bien online.
      if (mounted) context.read<ConnectivityService>().markHttpSucceeded();
    } catch (_) {
      // Réseau KO : on garde le cache, on n'affiche l'erreur que si on n'a
      // vraiment rien du tout à montrer.
      if (mounted) {
        context.read<ConnectivityService>().markHttpFailed();
        setState(() => _error = _convs == null || _convs!.isEmpty);
      }
    }
  }

  Future<void> _poll() async {
    if (!mounted) return;
    // Skip si offline : évite les timeouts qui figent l'UI.
    if (context.read<ConnectivityService>().isOffline) return;
    try {
      final convs = await context.read<ChatRepository>().listConversations();
      if (mounted) setState(() => _convs = convs);
      await ConversationCache.putAll(convs);
      if (mounted) context.read<ConnectivityService>().markHttpSucceeded();
    } catch (_) {
      if (mounted) context.read<ConnectivityService>().markHttpFailed();
    }
  }

  Future<void> _refresh() => _load();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;

    // Mode sélection : AppBar dédiée
    if (isSelecting) {
      return Scaffold(
        appBar: selectAppBar(
          title: "Conversations",
          onDelete: _deleteSelected,
          onCancel: clearSelection,
          onSelectAll: () =>
              selectAll((_convs ?? []).map((c) => c.id).toList()),
        ),
        body: MotifBackground(
          overlayOpacity: 0.92,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _buildList(),
          ),
        ),
      );
    }

    return MotifBackground(
      overlayOpacity: 0.92,
      child: Column(
        children: [
          if (user != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AlanyaColors.grey200, width: 0.5),
              ),
              child: Row(
                children: [
                  AvatarCircle(
                    name: user.pseudo ?? "?",
                    avatarUrl: user.avatarUrl,
                    radius: 22,
                    backgroundColor: AlanyaColors.terracotta,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AvatarViewerScreen(
                          name: user.pseudo ?? "Moi",
                          avatarUrl: user.avatarUrl,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.pseudo ?? "Moi",
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text("Numéro Alanya : ${user.publicNumber}",
                            style: const TextStyle(color: Colors.black54, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // --- Barre de recherche ---
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: "Rechercher une discussion…",
                prefixIcon: Icon(Icons.search, color: AlanyaColors.grey400, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: AlanyaColors.grey400, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AlanyaColors.grey200, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AlanyaColors.grey200, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AlanyaColors.terracotta, width: 1),
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_convs == null && !_error) {
      return const Center(child: CircularProgressIndicator(color: AlanyaColors.terracotta));
    }
    if (_error) {
      return ListView(children: const [
        SizedBox(height: 80),
        Center(child: Text("Erreur de chargement. Tire pour réessayer.")),
      ]);
    }
    final allConvs = _convs ?? [];
    if (allConvs.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 100),
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Aucune discussion.\nAppuie sur le bouton en bas pour accéder à tes contacts et démarrer une discussion.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
      ]);
    }

    // Filtre les conversations selon la recherche (WhatsApp-like)
    final convs = _searchQuery.isEmpty
        ? allConvs
        : allConvs.where((c) {
            final title = (c.title ?? '').toLowerCase();
            if (title.contains(_searchQuery)) return true;
            // Cherche dans les numéros des membres
            for (final m in c.members) {
              if (m.publicNumber.toLowerCase().contains(_searchQuery)) return true;
            }
            // Cherche dans le dernier message
            final content = (c.lastMessage?.content ?? '').toLowerCase();
            if (content.contains(_searchQuery)) return true;
            return false;
          }).toList();

    if (convs.isEmpty && _searchQuery.isNotEmpty) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: AlanyaColors.grey300),
              const SizedBox(height: 12),
              Text(
                "Aucun résultat pour \"$_searchQuery\"",
                style: TextStyle(color: AlanyaColors.grey500),
              ),
            ],
          ),
        ),
      ]);
    }

    return ListView.separated(
      itemCount: convs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _tile(convs[i]),
    );
  }

  Widget _tile(Conversation c) {
    final last = c.lastMessage;
    final preview = last == null
        ? "—"
        : (last.type == "AUDIO"
            ? "Message vocal"
            : last.type == "IMAGE"
                ? "Photo"
                : last.type == "FILE"
                    ? "Fichier"
                    : (last.content ?? "[${last.type}]"));
    final title = c.title ?? "Discussion";
    final myId = context.read<AuthController>().user?.id;
    final other = c.isGroup
        ? null
        : c.members.firstWhere(
            (m) => m.id != myId,
            orElse: () => c.members.isNotEmpty ? c.members.first : c.members.first,
          );

    return ListTile(
      leading: isSelecting
          ? selectCheckbox(c.id)
          : (c.isGroup
              ? CircleAvatar(
                  backgroundColor: AlanyaColors.forest,
                  child: const Icon(Icons.groups, color: Colors.white, size: 22),
                )
              : AvatarCircle(
                  name: title,
                  avatarUrl: c.avatarUrl,
                  radius: 22,
                  backgroundColor: AlanyaColors.gold,
                )),
      title: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          // F8 : badge épinglé
          if (c.isPinned)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.push_pin, size: 14, color: AlanyaColors.grey400),
            ),
        ],
      ),
      subtitle: Text(
        c.isGroup && c.members.isNotEmpty
            ? "${c.members.length} membres · $preview"
            : preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isSelecting
          ? null
          : (c.unread > 0
              ? CircleAvatar(
                  radius: 11,
                  backgroundColor: AlanyaColors.forest,
                  child: Text("${c.unread}",
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                )
              : null),
      onLongPress: isSelecting
          ? null
          : () => _showConversationOptions(c),
      onTap: () async {
        if (isSelecting) {
          toggleSelect(c.id);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              convId: c.id,
              title: title,
              isGroup: c.isGroup,
              memberNames: c.memberNames,
              avatarUrl: c.avatarUrl,
              otherUserId: other?.id,
              otherPublicNumber: other?.publicNumber,
              otherIsOnline: other?.isOnline ?? 0,
              otherLastSeen: other?.lastSeen,
            ),
          ),
        );
        _refresh();
      },
    );
  }

  /// Menu contextuel d'une conversation (long press).
  void _showConversationOptions(Conversation c) {
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
              child: Text(c.title ?? "Conversation",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                c.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: AlanyaColors.terracotta,
              ),
              title: Text(c.isPinned ? "Désépingler" : "Épingler"),
              onTap: () async {
                Navigator.pop(ctx);
                await context.read<ChatRepository>().pinConversation(c.id, !c.isPinned);
                _load();
              },
            ),
            ListTile(
              leading: Icon(
                c.isArchived ? Icons.unarchive : Icons.archive_outlined,
                color: AlanyaColors.chocolate,
              ),
              title: Text(c.isArchived ? "Désarchiver" : "Archiver"),
              onTap: () async {
                Navigator.pop(ctx);
                await context.read<ChatRepository>().archiveConversation(c.id, !c.isArchived);
                _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("Supprimer", style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Supprimer cette conversation ?"),
                    content: const Text("Cette action est irréversible."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Supprimer", style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (ok == true) {
                  await context.read<ChatRepository>().deleteConversation(c.id);
                  _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Affiche les conversations archivées dans un bottom sheet.
  Future<void> _showArchived() async {
    try {
      final repo = context.read<ChatRepository>();
      final data = await repo.listArchived();
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AlanyaColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text("Conversations archivées",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Expanded(
                child: data.isEmpty
                    ? const Center(
                        child: Text("Aucune conversation archivée",
                            style: TextStyle(color: Colors.black54)))
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: data.length,
                        itemBuilder: (_, i) {
                          final c = data[i];
                          final title = c.title ?? "Discussion";
                          return ListTile(
                            leading: AvatarCircle(
                              name: title,
                              avatarUrl: c.avatarUrl,
                              radius: 20,
                              backgroundColor: AlanyaColors.gold,
                            ),
                            title: Text(title),
                            trailing: TextButton(
                              onPressed: () async {
                                await repo.archiveConversation(c.id, false);
                                Navigator.pop(ctx);
                                _load();
                              },
                              child: const Text("Désarchiver"),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible de charger les archivées")),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final count = selectedCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Supprimer $count conversation(s) ?"),
        content: const Text("Cette action est irréversible."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Supprimer",
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;

    final repo = context.read<ChatRepository>();
    for (final id in selectedIds) {
      try {
        await repo.deleteConversation(id);
      } catch (_) {}
    }
    clearSelection();
    _load();
  }
}

class _StatusTab extends StatefulWidget {
  const _StatusTab();

  @override
  State<_StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<_StatusTab> {
  StatusFeed? _feed;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final feed = await context.read<StatusRepository>().feed();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _openCreate() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
    );
    if (published == true) _load();
  }

  Future<void> _openViewer(StatusGroup group, {required bool isMine}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatusViewerScreen(group: group, isMine: isMine)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = _feed?.me;
    final others = _feed?.others ?? [];
    return MotifBackground(
      overlayOpacity: 0.92,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            _myStatusTile(me),
            if (_error)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text("Erreur de chargement. Tire pour réessayer.")),
              ),
            if (others.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text("Récents",
                    style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
              ),
              ...others.map((g) => _statusTile(g, isMine: false)),
            ] else if (!_error && _feed != null && me == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    "Aucun statut pour le moment.\nPublie le tien avec le bouton +.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _myStatusTile(StatusGroup? me) {
    final has = me != null && me.statuses.isNotEmpty;
    final user = context.read<AuthController>().user;
    return ListTile(
      leading: Stack(
        children: [
          AvatarCircle(
            name: user?.pseudo ?? "?",
            avatarUrl: user?.avatarUrl,
            radius: 26,
            backgroundColor: AlanyaColors.terracotta,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AlanyaColors.forest,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 12),
            ),
          ),
        ],
      ),
      title: const Text("Mon statut", style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(has ? "${me!.statuses.length} statut(s)" : "Appuie pour ajouter"),
      onTap: has ? () => _openViewer(me!, isMine: true) : _openCreate,
      trailing: has
          ? IconButton(
              icon: Icon(Icons.camera_alt, color: AlanyaColors.terracotta),
              onPressed: _openCreate,
            )
          : null,
    );
  }

  Widget _statusTile(StatusGroup g, {required bool isMine}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: g.hasUnviewed ? AlanyaColors.forest : AlanyaColors.sand,
            width: 2.5,
          ),
        ),
        child: CircleAvatar(
          radius: 24,
          backgroundColor: AlanyaColors.gold,
          child: Text(g.displayName[0].toUpperCase(),
              style: const TextStyle(color: Colors.white)),
        ),
      ),
      title: Text(g.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(g.hasUnviewed ? "Nouveau" : "Vu"),
      onTap: () => _openViewer(g, isMine: isMine),
    );
  }
}

class _AiTab extends StatefulWidget {
  const _AiTab();

  @override
  State<_AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<_AiTab> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<AiMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final msgs = await context.read<AiRepository>().history();
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final repo = context.read<AiRepository>();
    final mine = AiMessage(
      id: "local-${DateTime.now().microsecondsSinceEpoch}",
      role: "USER",
      content: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, mine];
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();
    try {
      final reply = await repo.send(text);
      if (!mounted) return;
      setState(() => _messages = [..._messages, reply]);
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("L'assistant n'a pas répondu")));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MotifBackground(
      overlayOpacity: 0.9,
      child: Column(
        children: [
          // --- En-tête avec actions (supprimer / partager) ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AlanyaColors.terracotta),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Assistant Alanya",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: "Partager la conversation",
                  icon: const Icon(Icons.share_outlined, color: AlanyaColors.chocolate),
                  onPressed: _messages.isEmpty ? null : _shareConversation,
                ),
                IconButton(
                  tooltip: "Effacer la conversation",
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _messages.isEmpty ? null : _clearConversation,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AlanyaColors.terracotta))
                : (_messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 56, color: AlanyaColors.gold),
                              SizedBox(height: 12),
                              Text("Pose-moi une question pour commencer.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54)),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_sending ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (_sending && i == _messages.length) {
                            return _bubble("…", false, typing: true);
                          }
                          final m = _messages[i];
                          return _bubble(m.content, m.isUser, msg: m);
                        },
                      )),
          ),
          _composer(),
        ],
      ),
    );
  }

  /// Efface toute la conversation IA (après confirmation).
  Future<void> _clearConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Effacer la conversation ?"),
        content: const Text("Tous les échanges avec l'assistant seront supprimés."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Effacer")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<AiRepository>().clearHistory();
      if (mounted) setState(() => _messages = []);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Suppression impossible")),
        );
      }
    }
  }

  /// Partage la conversation (copie le texte dans le presse-papier).
  Future<void> _shareConversation() async {
    final text = _messages.map((m) {
      final who = m.isUser ? "Moi" : "IA";
      return "$who: ${m.content}";
    }).join("\n\n");
    await Clipboard.setData(ClipboardData(text: "Assistant Alanya\n\n$text"));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Conversation copiée dans le presse-papier")),
      );
    }
  }

  Widget _bubble(String text, bool mine, {bool typing = false, AiMessage? msg}) {
    return GestureDetector(
      onLongPress: msg == null ? null : () => _showAiMessageOptions(msg),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: mine ? AlanyaColors.terracotta : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: mine ? null : Border.all(color: AlanyaColors.sand),
          ),
          child: typing
              ? const Text("L'assistant écrit…",
                  style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic))
              : Text(text, style: TextStyle(color: mine ? Colors.white : AlanyaColors.ink)),
        ),
      ),
    );
  }

  /// Menu contextuel pour un message IA (copier, partager, supprimer).
  void _showAiMessageOptions(AiMessage msg) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy, color: AlanyaColors.chocolate),
              title: const Text("Copier"),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Copié dans le presse-papier")),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: AlanyaColors.forest),
              title: const Text("Partager"),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Message partagé (copié)")),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("Supprimer ce message"),
              onTap: () {
                Navigator.pop(ctx);
                _deleteAiMessage(msg);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Supprime un message IA local (optimiste).
  Future<void> _deleteAiMessage(AiMessage msg) async {
    setState(() {
      _messages = _messages.where((m) => m.id != msg.id).toList();
    });
    // Note : l'API ne permet pas de supprimer un message individuel, seulement
    // toute la conversation. On supprime localement pour l'UX.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Message supprimé"),
        action: SnackBarAction(
          label: "Annuler",
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _messages = [..._messages, msg]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            });
          },
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: AlanyaColors.cream,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: "Demande quelque chose à l'IA…",
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AlanyaColors.forest,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sending ? null : _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.label, required this.soon});
  final IconData icon;
  final String label;
  final String soon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AlanyaColors.gold),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("$soon — bientôt", style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
