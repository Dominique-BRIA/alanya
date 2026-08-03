import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../core/alanya_id_formatter.dart';
import '../../core/whatsapp_text.dart';

import '../../core/connectivity_service.dart';
import '../../core/conversation_cache.dart';
import '../../core/push_service.dart';
import '../../core/in_app_notifier.dart';
import '../../core/ringtone_service.dart';
import '../../core/notification_settings.dart';
import '../../core/realtime_client.dart';
import '../../core/call_cache.dart';
import '../../core/call_status.dart';
import '../../models/call_record.dart';
import '../../models/ai_message.dart';
import '../../models/auth_user.dart';
import '../../models/conversation.dart';
import '../../models/status.dart';
import '../../theme/alanya_theme.dart';
import '../../core/theme_controller.dart';
import '../../widgets/alanya_wordmark.dart';
import '../../widgets/alanya_nav_bar.dart';
import '../../widgets/avatar_circle.dart';
import '../../widgets/motif_background.dart';
import '../../widgets/multi_select_mixin.dart';
import '../account/screens/avatar_viewer_screen.dart';
import '../account/screens/profile_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../settings/screens/devices_screen.dart';
import '../ai/ai_repository.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_repository.dart';
import '../chat/screens/chat_screen.dart';
import '../calls/screens/dialer_screen.dart';
import '../contacts/screens/contacts_screen.dart';
import '../chat/screens/new_group_screen.dart';
import '../contacts/screens/add_contact_screen.dart';
import '../contacts/screens/new_chat_screen.dart';
import '../calls/call_controller.dart';
import '../calls/call_listener.dart';
import '../calls/calls_repository.dart';
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
          // letterSpacing réduit de 4 à 2 : « ALANYA WORK » fait onze
          // caractères, et l'AppBar porte aussi des actions.
          title: const AlanyaWordmark(fontSize: 22, letterSpacing: 2, height: 1),
          actions: [
            IconButton(
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark ? Icons.wb_sunny : Icons.nightlight_round,
                color: Theme.of(context).brightness == Brightness.dark ? AlanyaColors.terracottaNuit : AlanyaColors.terracotta,
              ),
              tooltip: Theme.of(context).brightness == Brightness.dark ? "Passer au mode clair" : "Passer au mode sombre",
              onPressed: () {
                final themeCtrl = context.read<ThemeController>();
                themeCtrl.basculerClairSombre(
                  Theme.of(context).brightness == Brightness.dark,
                );
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == "settings") {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                } else if (v == "devices") {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DevicesScreen()),
                  );
                } else if (v == "logout") {
                  context.read<AuthController>().logout();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: "devices", child: ListTile(leading: Icon(Icons.devices_outlined), title: Text("Appareils connectés"), contentPadding: EdgeInsets.zero,)),
                const PopupMenuItem(value: "settings", child: ListTile(leading: Icon(Icons.settings_outlined), title: Text("Paramètres"), contentPadding: EdgeInsets.zero,)),
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
                // Nuit : icône sombre sur la terre cuite (contraste du modèle).
                child: Icon(Icons.edit,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF160B06)
                        : Colors.white),
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
    with MultiSelectMixin<_ConversationsTab>, WidgetsBindingObserver {
  List<Conversation>? _convs;
  List<Conversation>? _archivedConvs;
  Map<String, CallRecord> _lastCallPerConv = {};
  bool _error = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _tabFilter = 0;
  bool _wasBusy = false;

  // Formalisme centralisé – voir lib/core/call_status.dart
  String _preciseCallStatus(CallRecord c) => CallStatusFormalisme.preciseLabel(c);
  IconData _callIconFor(CallRecord c) => CallStatusFormalisme.iconFor(c);
  Color _callColorFor(CallRecord c, BuildContext context) => CallStatusFormalisme.colorFor(c, danger: dangerOf(context), positive: positiveOf(context));
  String _formatDateTimeShort(DateTime dt) => CallStatusFormalisme.formatDateTime(dt);

  /// Recharge les appels : le cache pour l'affichage immédiat, puis le serveur
  /// qui fait autorité.
  ///
  /// ⚠️ La version précédente n'interrogeait le serveur QUE si le cache était
  /// vide. Elle ne pouvait donc jamais découvrir un appel nouveau : dès qu'un
  /// seul appel était en cache, tous les rechargements relisaient ce même
  /// cache. C'est ce qui rendait le rafraîchissement inopérant ici, alors même
  /// que l'événement WebSocket arrivait bien.
  Future<void> _loadCalls() async {
    try {
      final caches = await CallCache.getAll();
      if (caches.isNotEmpty && mounted) _appliqueCalls(caches);
    } catch (_) {}
    try {
      final calls = await context.read<CallsRepository>().history();
      if (!mounted) return;
      _appliqueCalls(calls);
      // Le cache est réalimenté ici, sinon il resterait figé sur ce que
      // l'écran Appels y a déposé la dernière fois.
      await CallCache.putAll(calls);
    } catch (_) {}
  }

  void _appliqueCalls(List<CallRecord> calls) {
    final map = <String, CallRecord>{};
    for (final call in calls) {
      final convId = call.convId;
      if (convId == null) continue;
      final existing = map[convId];
      if (existing == null || call.startedAt.isAfter(existing.startedAt)) {
        map[convId] = call;
      }
    }
    if (mounted) setState(() => _lastCallPerConv = map);
  }

  /// Insère un appel poussé par le serveur, sans requête.
  ///
  /// N'écrase l'aperçu de la conversation que si cet appel est plus RÉCENT que
  /// celui déjà retenu : un appel clos tardivement ne doit pas repasser devant
  /// un appel plus frais.
  ///
  /// Réarme le garde anti-rafale, l'état étant déjà à jour.
  void _integreAppel(CallRecord c) {
    final convId = c.convId;
    if (convId == null) return;
    _dernierRafraichissementAppels = DateTime.now();
    final connu = _lastCallPerConv[convId];
    if (connu != null && connu.startedAt.isAfter(c.startedAt)) return;
    if (!mounted) return;
    setState(() {
      _lastCallPerConv = {..._lastCallPerConv, convId: c};
    });
  }

  /// Point d'entrée des rafraîchissements AUTOMATIQUES (retour au premier plan,
  /// reconnexion WebSocket, fin d'appel). Ils se déclenchent souvent ensemble —
  /// revenir dans l'app reconnecte le WebSocket dans la foulée — d'où ce garde
  /// qui évite deux requêtes coup sur coup. Le pull-to-refresh, lui, appelle
  /// `_loadCalls` directement : une action explicite ne doit jamais être ignorée.
  DateTime? _dernierRafraichissementAppels;
  void _rafraichitAppels() {
    final maintenant = DateTime.now();
    final dernier = _dernierRafraichissementAppels;
    if (dernier != null &&
        maintenant.difference(dernier) < const Duration(milliseconds: 1500)) {
      return;
    }
    _dernierRafraichissementAppels = maintenant;
    _loadCalls();
  }

  void _onCallActivity() {
    try {
      final busy = context.read<CallController>().isBusy;
      if (_wasBusy && !busy) {
        // Un appel vient de se terminer => l'historique contient un nouveau MISSED/ENDED
        _loadCalls();
        _poll();
      }
      _wasBusy = busy;
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadCalls();
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
      } else if (t == "call_ended") {
        // Le serveur pousse l'appel COMPLET : on l'insère, sans rien recharger.
        final brut = e["call"];
        if (brut is Map) {
          _integreAppel(CallRecord.fromJson(Map<String, dynamic>.from(brut)));
        }
      } else if (t == "call_state" || t == "incoming_call") {
        // Repli : un serveur qui n'envoie pas encore `call_ended` ne signale que
        // le changement d'état, il faut alors aller chercher l'appel. Le garde
        // de `_rafraichitAppels` absorbe le doublon quand les deux arrivent.
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _rafraichitAppels();
        });
      } else if (t == "ws_connected") {
        // La connexion vient de se rétablir : tout ce qui s'est passé pendant
        // la coupure n'a jamais été reçu et ne le sera jamais, un événement
        // WebSocket ne se rejoue pas. On rattrape par une requête.
        _rafraichitAppels();
        _poll();
      }
    });
    // Rafraîchissement de repli (dernier message, non-lus) si le WS est coupé.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    // Ecoute fin d'appel pour auto-refresh sans pull-to-refresh
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<CallController>().addListener(_onCallActivity);
      } catch (_) {}
    });
  }

  /// Affiche une notification locale pour un message entrant.
  void _showMessageNotification(Map<String, dynamic> e) {
    // Confidentialité/réglages : notifications de messages désactivées → rien.
    if (!NotificationSettings.instance.messagesOn) return;
    final msg = e["message"] as Map<String, dynamic>?;
    if (msg == null) return;

    final convId = msg["convId"] as String? ?? "";
    final content = msg["content"] as String?;
    final type = msg["type"] as String? ?? "TEXT";
    if (type == "SYSTEM") return; // pas de notif pour les messages système

    // Le bandeau interne est muet : sans ce son, un message reçu alors que
    // l'app est ouverte sur un autre écran passait totalement inaperçu.
    // L'anti-rafale est dans RingtoneService.
    RingtoneService.instance.playMessageReceived();

    // Trouve la conversation (titre + avatar)
    Conversation? conv;
    for (final c in _convs ?? <Conversation>[]) {
      if (c.id == convId) {
        conv = c;
        break;
      }
    }
    final title = conv?.title ?? "Nouveau message";

    // Aperçu du message selon le type — on retire les marqueurs pour les
    // notifications système, qui ne peuvent pas afficher de rich text.
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
        // Si c'est un message formaté, on n'affiche pas les * _ ~ dans la notif
        body = content == null ? "Nouveau message" : sansMarqueursWhatsApp(content);
        if (body.trim().isEmpty) body = "Nouveau message";
    }

    // Aperçu désactivé → texte générique (dans le bandeau ET la notif système).
    if (!NotificationSettings.instance.previewOn) {
      body = "Nouveau message";
    }

    // Bandeau in-app (heads-up custom glassmorphism) au-dessus de toutes les
    // pages : regroupement par conversation (groupKey) + réponse rapide inline.
    final conversation = conv;
    final chat = context.read<ChatRepository>();
    InAppNotifier.instance.showMessage(
      title: title,
      body: body,
      avatarUrl: conversation?.avatarUrl,
      groupKey: convId,
      onQuickReply: convId.isEmpty ? null : (text) => chat.sendText(convId, text),
      onTap: () {
        PushService.navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title: title,
            isGroup: conversation?.isGroup ?? false,
          ),
        ));
      },
    );

    // Affiche aussi la notification système.
    PushService.instance.show(
      title: title,
      body: body,
      id: convId.hashCode,
      payload: {"type": "message", "convId": convId},
    );
  }

  /// Retour au premier plan : le cas le plus fréquent pour un appel manqué,
  /// puisqu'on n'était par définition pas devant l'écran quand il est arrivé.
  ///
  /// Ne fait pas doublon avec `ws_connected` : si l'app n'est restée en
  /// arrière-plan que quelques secondes, la connexion n'est pas tombée et aucun
  /// événement de reconnexion n'arrivera. Quand les deux se déclenchent
  /// ensemble, le garde de `_rafraichitAppels` absorbe le second.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _rafraichitAppels();
      _poll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _rtSub?.cancel();
    try {
      context.read<CallController>().removeListener(_onCallActivity);
    } catch (_) {}
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
    // Charge les appels pour l'aperçu type WhatsApp
    _loadCalls();
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

      // Charge les archivées en arrière-plan
      try {
        final archived = await context.read<ChatRepository>().listArchived();
        if (mounted) setState(() => _archivedConvs = archived);
      } catch (_) {}

      // Rafraîchit les appels pour l'aperçu
      _loadCalls();
    } catch (_) {
      if (mounted) context.read<ConnectivityService>().markHttpFailed();
    }
  }

  Future<void> _refresh() async {
    await _load();
    await _loadCalls();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final searchIconColor =
        themed(context, light: AlanyaColors.grey400, dark: AlanyaColors.craie2);
    final searchBorder =
        themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne);

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
          plainInDark: true,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _buildList(),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: MotifBackground(
        overlayOpacity: 0.92,
        plainInDark: true,
        child: Column(
        children: [
          if (user != null)
            // IntrinsicHeight + stretch : sans lui, la Row centrerait le
            // bouton sur sa hauteur et il ne s'alignerait ni en haut ni en bas
            // avec la carte. Ici les deux blocs font exactement la même
            // hauteur, celle imposée par la carte de profil.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _carteProfil(context, user)),
                  _boutonSaisirId(context),
                  const SizedBox(width: 12),
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
                prefixIcon: Icon(Icons.search, color: searchIconColor, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: searchIconColor, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: themed(context,
                    light: Colors.white, dark: surfacesOf(context).surface),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: searchBorder, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: searchBorder, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: themed(context,
                          light: AlanyaColors.terracotta,
                          dark: AlanyaColors.terracottaNuit),
                      width: 1),
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          // --- Onglets : Tous / Non lues / Groupes ---
          TabBar(
            tabs: const [
              Tab(text: "Tous"),
              Tab(text: "Non lues"),
              Tab(text: "Groupes"),
            ],
            labelColor: AlanyaColors.terracotta,
            unselectedLabelColor: AlanyaColors.craie2,
            indicatorColor: AlanyaColors.terracotta,
            indicatorWeight: 2.5,
            onTap: (i) => setState(() => _tabFilter = i),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildList(),
            ),
          ),
        ],
      ),
    ),
  );
  }

  /// Carte d'identité de l'utilisateur : avatar, nom, Alanya ID.
  ///
  /// Extraite du `build` pour partager sa ligne avec le bouton « Saisir ID ».
  /// La marge droite tombe de 12 à 8 : l'écart avec le bouton est repris par le
  /// `SizedBox` de la ligne, sinon les deux se toucheraient.
  Widget _carteProfil(BuildContext context, AuthUser user) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 8, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: themed(context,
            light: Colors.white, dark: surfacesOf(context).surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: themed(context,
                light: AlanyaColors.grey200, dark: AlanyaColors.ligne),
            width: 0.5),
      ),
      child: Row(
        children: [
          AvatarCircle(
            name: user.nom ?? user.pseudo ?? "?",
            avatarUrl: user.avatarUrl,
            radius: 22,
            backgroundColor: AlanyaColors.terracotta,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AvatarViewerScreen(
                  name: user.nom ?? user.pseudo ?? "Moi",
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
                // La carte identifie l'utilisateur par son nom. `nom` est
                // nullable : repli sur le pseudo pour les comptes qui
                // n'en ont pas encore, plutôt qu'un « Moi » anonyme.
                Text(user.nom ?? user.pseudo ?? "Moi",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("Alanya ID : ${formatAlanyaId(user.publicNumber)}",
                    style: TextStyle(
                        color: alanyaIdOf(context, Colors.black54),
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bouton « Saisir ID » : ouvre le clavier d'appel, exactement comme le
  /// bouton de l'écran Appels. Même symbole des deux côtés — ici avec son
  /// libellé, là-bas sans.
  ///
  /// Sa hauteur n'est pas fixée : l'`IntrinsicHeight` de la ligne l'étire sur
  /// celle de la carte de profil. La marge haute reprend celle de la carte,
  /// pour que les deux blocs commencent au même niveau.
  Widget _boutonSaisirId(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      // Fond plein dans le vert du logotype, identique sur les quatre thèmes :
      // c'est la couleur de la marque, elle ne doit pas dériver. Icône et
      // libellé passent au blanc — sur #098084 le contraste est de 4,74:1,
      // au-dessus du seuil de lisibilité. Plus de bordure : elle n'avait de
      // sens que sur le fond clair d'origine.
      child: Material(
        color: AlanyaColors.logoVert,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DialerScreen()),
          ),
          // Tout le contenu est littéral depuis que les couleurs ne dépendent
          // plus du thème : le sous-arbre entier devient constant, donc
          // construit une seule fois.
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone, color: Colors.white, size: 24),
                SizedBox(height: 2),
                Text(
                  "Saisir ID",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final muted =
        themed(context, light: Colors.black54, dark: AlanyaColors.craie2);
    final muted2 = themed(context,
        light: AlanyaColors.grey500, dark: AlanyaColors.craie2);
    if (_convs == null && !_error) {
      return Center(
        child: CircularProgressIndicator(
          color: themed(context,
              light: AlanyaColors.terracotta, dark: AlanyaColors.terracottaNuit),
        ),
      );
    }
    if (_error) {
      return ListView(children: const [
        SizedBox(height: 80),
        Center(child: Text("Erreur de chargement. Tire pour réessayer.")),
      ]);
    }
    final allConvs = _convs ?? [];
    final baseConvs = _tabFilter == 0
        ? allConvs
        : (_tabFilter == 1
            ? allConvs.where((c) => c.unread > 0).toList()
            : allConvs.where((c) => c.isGroup).toList());
    if (baseConvs.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 100),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Aucune discussion.\nAppuie sur le bouton en bas pour accéder à tes contacts et démarrer une discussion.",
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ),
        ),
      ]);
    }

    // Filtre les conversations selon la recherche (WhatsApp-like)
    final convs = _searchQuery.isEmpty
        ? baseConvs
        : baseConvs.where((c) {
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
              Icon(Icons.search_off,
                  size: 48,
                  color: themed(context,
                      light: AlanyaColors.grey300, dark: AlanyaColors.craie2)),
              const SizedBox(height: 12),
              Text(
                "Aucun résultat pour \"$_searchQuery\"",
                style: TextStyle(color: muted2),
              ),
            ],
          ),
        ),
      ]);
    }

    // WhatsApp-style : section archivées en haut si présentes
    final archivedCount = _archivedConvs?.length ?? 0;

    return ListView(
      children: [
        // Bouton "Conversations archivées" style WhatsApp
        if (archivedCount > 0 && _searchQuery.isEmpty)
          ListTile(
            leading: Icon(Icons.archive_outlined, color: muted2, size: 24),
            title: Text(
              "Conversations archivées",
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: muted2,
                fontSize: 15,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AlanyaColors.terracotta.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "$archivedCount",
                style: TextStyle(
                  color: AlanyaColors.terracotta,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            onTap: _showArchived,
          ),
        if (archivedCount > 0 && _searchQuery.isEmpty)
          const Divider(height: 1),
        // Liste des conversations
        ...convs.map((c) => _tile(c)),
      ],
    );
  }

  Widget _tile(Conversation c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final last = c.lastMessage;
    final lastCall = _lastCallPerConv[c.id];

    // Détermine si l'appel est plus récent que le dernier message
    bool useCallPreview = false;
    if (lastCall != null) {
      if (last == null) {
        useCallPreview = true;
      } else {
        // Compare dates : si l'appel est après le dernier message, on affiche l'appel
        try {
          if (lastCall.startedAt.isAfter(last.createdAt)) {
            useCallPreview = true;
          }
        } catch (_) {}
      }
    }

    // Libellés pour les types non-texte
    String typeLabel() {
      if (last == null) return "—";
      switch (last.type) {
        case "AUDIO":
          return "Message vocal";
        case "IMAGE":
          return "Photo";
        case "VIDEO":
          return "Vidéo";
        case "FILE":
          return "Fichier";
        default:
          return last.content ?? "[${last.type}]";
      }
    }

    // Construit l'aperçu formaté : si TEXT on affiche en formaté (sans *),
    // sinon libellé simple. Pour les groupes on préfixe avec le compteur.
    // Si un appel est plus récent, on affiche le statut d'appel façon WhatsApp.
    Widget buildPreview({required TextStyle? style}) {
      final baseStyle = style ??
          TextStyle(
            fontSize: 13,
            color: themed(context,
                light: AlanyaColors.grey600, dark: AlanyaColors.craie2),
          );

      // Si on doit afficher l'appel comme dernier événement (WhatsApp-like)
      if (useCallPreview && lastCall != null) {
        final callStatus = _preciseCallStatus(lastCall);
        final icon = _callIconFor(lastCall);
        final time = _formatDateTimeShort(lastCall.startedAt);
        final color = _callColorFor(lastCall, context);
        return Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                "$callStatus · $time",
                style: baseStyle.copyWith(
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }

      if (last == null) {
        return Text("—", style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
      }
      final isText = last.type == "TEXT" && (last.content?.isNotEmpty ?? false);
      if (!isText) {
        final label = typeLabel();
        final full = c.isGroup && c.members.isNotEmpty
            ? "${c.members.length} membres · $label"
            : label;
        return Text(full,
            style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
      }
      // TEXT formaté
      final raw = last.content!.trim();
      // Coupe à 120 char pour ne pas surcharger le ListTile avec un pavé
      final trimmed = raw.length > 120 ? "${raw.substring(0, 120)}…" : raw;
      final spans = spansWhatsApp(trimmed);
      if (c.isGroup && c.members.isNotEmpty) {
        final prefix = "${c.members.length} membres · ";
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              TextSpan(text: prefix),
              ...spans,
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      return Text.rich(
        TextSpan(style: baseStyle, children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final title = c.title ?? "Discussion";
    final myId = context.read<AuthController>().user?.id;
    final other = c.isGroup
        ? null
        : c.members.firstWhere(
            (m) => m.id != myId,
            orElse: () => c.members.isNotEmpty ? c.members.first : c.members.first,
          );

    final subtitleStyle = TextStyle(
      fontSize: 13,
      color: themed(context,
          light: AlanyaColors.grey600, dark: AlanyaColors.craie2),
    );

    return ListTile(
      leading: isSelecting
          ? selectCheckbox(c.id)
          : (c.isGroup
              ? CircleAvatar(
                  // Nuit : l'indigo porte l'identité (avatars, groupes).
                  backgroundColor:
                      isDark ? AlanyaColors.indigo : AlanyaColors.forest,
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
              child: Icon(Icons.push_pin,
                  size: 14,
                  color: isDark ? AlanyaColors.craie2 : AlanyaColors.grey400),
            ),
        ],
      ),
      subtitle: buildPreview(style: subtitleStyle),
      trailing: isSelecting
          ? null
          : (c.unread > 0
              // Modèle Nuit : le non-lu est un accent terre cuite sur texte sombre.
              ? CircleAvatar(
                  radius: 11,
                  backgroundColor:
                      isDark ? AlanyaColors.terracottaNuit : AlanyaColors.forest,
                  child: Text("${c.unread}",
                      style: TextStyle(
                        color: isDark ? const Color(0xFF140A06) : Colors.white,
                        fontSize: 12,
                      )),
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
    if (_archivedConvs == null || _archivedConvs!.isEmpty) return;

    final repo = context.read<ChatRepository>();
    final handle =
        themed(context, light: AlanyaColors.grey300, dark: AlanyaColors.craie2);
    final muted2 = themed(context,
        light: AlanyaColors.grey500, dark: AlanyaColors.craie2);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: handle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text("Conversations archivées",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text("${_archivedConvs!.length}",
                      style: TextStyle(color: muted2)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _archivedConvs!.length,
                itemBuilder: (_, i) {
                  final c = _archivedConvs![i];
                  final title = c.title ?? "Discussion";
                  // Aperçu formaté également dans les archivées : on affiche
                  // le style réel (gras/italique) et plus les marqueurs.
                  Widget archivedPreview() {
                    final last = c.lastMessage;
                    if (last == null || (last.content?.isEmpty ?? true)) {
                      return Text("—",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted2));
                    }
                    if (last.type != "TEXT") {
                      return Text(
                        last.type == "AUDIO"
                            ? "Message vocal"
                            : last.type == "IMAGE"
                                ? "Photo"
                                : last.type == "VIDEO"
                                    ? "Vidéo"
                                    : "Fichier",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted2),
                      );
                    }
                    final trimmed = last.content!.length > 100
                        ? "${last.content!.substring(0, 100)}…"
                        : last.content!;
                    return Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 12, color: muted2),
                        children: spansWhatsApp(trimmed),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }

                  return ListTile(
                    leading: AvatarCircle(
                      name: title,
                      avatarUrl: c.avatarUrl,
                      radius: 20,
                      backgroundColor: AlanyaColors.gold,
                    ),
                    title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: archivedPreview(),
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
    final muted =
        themed(context, light: Colors.black54, dark: AlanyaColors.craie2);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Status"),
      ),
      body: MotifBackground(
        overlayOpacity: 0.92,
        plainInDark: true,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text("Récents",
                      style: TextStyle(
                          color: muted, fontWeight: FontWeight.bold)),
                ),
                ...others.map((g) => _statusTile(g, isMine: false)),
              ] else if (!_error && _feed != null && me == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      "Aucun statut pour le moment.\nPublie le tien avec le bouton +.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _myStatusTile(StatusGroup? me) {
    final has = me != null && me.statuses.isNotEmpty;
    final user = context.read<AuthController>().user;
    final theme = Theme.of(context);
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
                color: theme.brightness == Brightness.dark
                    ? AlanyaColors.terracottaNuit
                    : AlanyaColors.forest,
                shape: BoxShape.circle,
                border: Border.all(
                    color: themed(context,
                        light: Colors.white, dark: surfacesOf(context).fond),
                    width: 2),
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
              icon: Icon(Icons.camera_alt,
                  color: theme.brightness == Brightness.dark
                      ? AlanyaColors.terracottaNuit
                      : AlanyaColors.terracotta),
              onPressed: _openCreate,
            )
          : null,
    );
  }

  Widget _statusTile(StatusGroup g, {required bool isMine}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unviewedRing =
        isDark ? AlanyaColors.terracottaNuit : AlanyaColors.forest;
    final viewedRing = isDark ? AlanyaColors.ligne : AlanyaColors.sand;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: g.hasUnviewed ? unviewedRing : viewedRing,
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

class _AiTabState extends State<_AiTab> with TickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<AiMessage> _messages = [];
  String? _threadId; // conversation courante ; null = nouvelle conversation
  bool _loading = true;
  bool _sending = false;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Ouvre la conversation la plus récente (ou une nouvelle si aucune).
  Future<void> _load() async {
    try {
      final repo = context.read<AiRepository>();
      final threads = await repo.threads();
      if (!mounted) return;
      if (threads.isEmpty) {
        setState(() {
          _threadId = null;
          _messages = [];
          _loading = false;
        });
        return;
      }
      final tid = threads.first.id;
      final msgs = await repo.threadMessages(tid);
      if (!mounted) return;
      setState(() {
        _threadId = tid;
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _newConversation() {
    setState(() {
      _threadId = null;
      _messages = [];
    });
    _inputCtrl.clear();
    _switchToDiscussion();
  }

  Future<void> _openThread(String threadId) async {
    setState(() => _loading = true);
    try {
      final msgs = await context.read<AiRepository>().threadMessages(threadId);
      if (!mounted) return;
      setState(() {
        _threadId = threadId;
        _messages = msgs;
        _loading = false;
      });
      _switchToDiscussion();
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchToDiscussion() {
    if (_tabCtrl.index != 0) {
      _tabCtrl.animateTo(0);
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
      final (tid, reply) = await repo.send(text, threadId: _threadId);
      if (!mounted) return;
      setState(() {
        _threadId = tid;
        _messages = [..._messages, reply];
      });
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
        // --- Onglets Discussion / Mes Conversations ---
        TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: "Discussion"),
            Tab(text: "Mes Conversations"),
          ],
          labelColor: AlanyaColors.terracotta,
          unselectedLabelColor: AlanyaColors.craie2,
          indicatorColor: AlanyaColors.terracotta,
          indicatorWeight: 2.5,
        ),
        Expanded(
          child: _tabCtrl.index == 0 ? _buildDiscussion() : _buildThreadsList(),
        ),
        if (_tabCtrl.index == 0) _composer(),
      ],
    ),
  );
  }

  /// Supprime la conversation IA courante (après confirmation).
  Future<void> _clearConversation() async {
    final tid = _threadId;
    if (tid == null) {
      _newConversation();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Supprimer cette conversation ?"),
        content: const Text("Les échanges de cette conversation seront supprimés."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Supprimer")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<AiRepository>().deleteThread(tid);
      if (mounted) _newConversation();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Suppression impossible")),
        );
      }
    }
  }

  /// Feuille listant les conversations IA (ouvrir / nouvelle / supprimer).
  void _showThreads() {
    final repo = context.read<AiRepository>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text("Mes conversations",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<AiThreadSummary>>(
                future: repo.threads(),
                builder: (fctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final threads = snap.data ?? const [];
                  if (threads.isEmpty) {
                    return const Center(
                        child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("Aucune conversation. Pose une question !"),
                    ));
                  }
                  return ListView.separated(
                    controller: scroll,
                    itemCount: threads.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = threads[i];
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline,
                            color: AlanyaColors.terracotta),
                        title: Text(t.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: t.lastMessage != null
                            ? Text(t.lastMessage!,
                                maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed: () async {
                            try {
                              await repo.deleteThread(t.id);
                            } catch (_) {}
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (_threadId == t.id) _newConversation();
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _openThread(t.id);
                          _switchToDiscussion();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onLongPress: msg == null ? null : () => _showAiMessageOptions(msg),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            // Nuit : envoyé = indigo (identité), reçu = nuit-3.
            color: mine
                ? (isDark ? AlanyaColors.indigo : AlanyaColors.terracotta)
                : (isDark ? surfacesOf(context).surfaceHaute : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: mine
                ? null
                : Border.all(
                    color: isDark ? AlanyaColors.ligne : AlanyaColors.sand),
          ),
          child: typing
              ? Text("L'assistant écrit…",
                  style: TextStyle(
                      color:
                          isDark ? AlanyaColors.craie2 : Colors.black54,
                      fontStyle: FontStyle.italic))
              : Text(text,
                  style: TextStyle(
                      color: mine
                          ? Colors.white
                          : (isDark ? AlanyaColors.craie : AlanyaColors.ink))),
        ),
      ),
    );
  }

  Widget _buildDiscussion() {
    return _loading
        ? Center(child: CircularProgressIndicator(color: Theme.of(context).brightness == Brightness.dark ? AlanyaColors.terracottaNuit : AlanyaColors.terracotta))
        : (_messages.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 56, color: AlanyaColors.gold),
                      const SizedBox(height: 12),
                      Text("Pose-moi une question pour commencer.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark ? AlanyaColors.craie2 : Colors.black54)),
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
              ));
  }

  Widget _buildThreadsList() {
    final repo = context.read<AiRepository>();
    return FutureBuilder<List<AiThreadSummary>>(
      future: repo.threads(),
      builder: (fctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final threads = snap.data ?? const [];
        return Column(
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AlanyaColors.terracotta,
                child: Icon(Icons.add, color: Colors.white),
              ),
              title: const Text("Nouvelle conversation", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: _newConversation,
            ),
            const Divider(height: 1),
            Expanded(
              child: threads.isEmpty
                  ? const Center(child: Text("Aucune conversation. Pose une question !"))
                  : ListView.separated(
                      itemCount: threads.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final t = threads[i];
                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline, color: AlanyaColors.terracotta),
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: t.lastMessage != null ? Text(t.lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20),
                            onSelected: (v) async {
                              if (v == 'delete') {
                                await repo.deleteThread(t.id);
                                if (_threadId == t.id) _newConversation();
                              } else if (v == 'share') {
                                final text = "Conversation: ${t.title}";
                                await Clipboard.setData(ClipboardData(text: text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Lien copié")),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'share', child: Text("Partager")),
                              const PopupMenuItem(value: 'delete', child: Text("Supprimer", style: TextStyle(color: Colors.red))),
                            ],
                          ),
                          onTap: () => _openThread(t.id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Menu contextuel pour un message IA (copier, partager, supprimer).
  void _showAiMessageOptions(AiMessage msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.copy,
                  color:
                      isDark ? AlanyaColors.craie2 : AlanyaColors.chocolate),
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
              leading: Icon(Icons.share,
                  color:
                      isDark ? AlanyaColors.indigoLight : AlanyaColors.forest),
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
              leading: Icon(Icons.delete_outline,
                  color: isDark ? AlanyaColors.erreurNuit : Colors.red),
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
        color: themed(context,
            light: surfacesOf(context).fond, dark: surfacesOf(context).surface),
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
          Text("$soon — bientôt",
              style: TextStyle(
                  color: themed(context,
                      light: Colors.black54, dark: AlanyaColors.craie2))),
        ],
      ),
    );
  }
}
