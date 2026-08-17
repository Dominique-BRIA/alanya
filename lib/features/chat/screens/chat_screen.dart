// chat_screen.dart — WhatsApp previews COMPLET (thumbnails vidéo, PDF, waveform, grille)
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../core/message_cache.dart';
import '../../../core/whatsapp_text.dart';
import '../../../core/whatsapp_format_input.dart';
import '../../../core/whatsapp_editing_controller.dart';
import '../../../core/outbox.dart';
import '../../../core/call_cache.dart';
import '../../../core/call_status.dart';
import '../../../models/call_record.dart';
import '../../calls/calls_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/audio_player.dart';
import '../../../core/downloader.dart';
import '../../../core/notification_settings.dart';
import '../../../core/presence_store.dart';
import '../../../core/realtime_client.dart';
import '../../../core/ringtone_service.dart';
import '../../../core/token_storage.dart';
import '../../../core/voice_recorder.dart';
import '../../../core/locale_controller.dart';
import '../../../core/translate_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/message.dart';
import '../../../models/message_payload.dart';
import '../../../models/conversation.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/contact_share_sheet.dart';
import '../../../widgets/motif_background.dart';
import '../../account/screens/avatar_viewer_screen.dart';
import '../../auth/auth_controller.dart';
import '../../calls/call_controller.dart';
import '../../calls/message_erreur_appel.dart';
import '../../calls/screens/active_call_screen.dart';
import '../../contacts/contacts_repository.dart';
import '../../contacts/screens/contact_info_screen.dart';
import '../../group/screens/group_info_screen.dart';
import '../../media/media_repository.dart';
import '../chat_repository.dart';
import '../envoi_media.dart';
import '../groupe_medias.dart';
import '../widgets/activity_indicator.dart';
import 'pdf_viewer_screen.dart';
import 'media_caption_screen.dart';
import 'media_gallery_picker_screen.dart';
import 'location_share_screen.dart';

// ── Imports previews WhatsApp ──
import '../../../widgets/media/image_bubble.dart';
import '../../../widgets/media/video_bubble.dart';
import '../../../widgets/media/document_bubble.dart';
import '../../../widgets/media/audio_bubble.dart';
import '../../../widgets/media/reply_media_preview.dart';
import '../../../widgets/media/media_grid.dart';
import '../../../widgets/media/contact_bubble.dart';
import '../../../widgets/media/location_bubble.dart';
import '../../../widgets/media/sending_media_bubble.dart';
import '../../../core/media_helper.dart';
import '../chat_media_integration.dart';
import '../../../widgets/media/gps_preview.dart';
import 'media_gallery_viewer.dart';
import '../../../widgets/media/media_picker_sheet.dart';

class ChatScreen extends StatefulWidget {
  static String? activeConvId;
  const ChatScreen({
    super.key,
    required this.convId,
    required this.title,
    this.isGroup = false,
    this.memberNames = const {},
    this.avatarUrl,
    this.otherUserId,
    this.otherPublicNumber,
    this.otherStatusMsg,
    this.contactId,
    this.isBlocked = false,
    this.otherIsOnline = 0,
    this.otherLastSeen,
  });
  final String convId;
  final String title;
  final bool isGroup;
  final Map<String, String> memberNames;
  final String? avatarUrl;
  final String? otherUserId;
  final String? otherPublicNumber;
  final String? otherStatusMsg;
  final String? contactId;
  final bool isBlocked;
  final int otherIsOnline;
  final DateTime? otherLastSeen;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with
        ChatMediaIntegrationMixin,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  /// Battement du chevron au-dessus du micro, qui indique « glisse vers le
  /// haut pour verrouiller ». Il tourne en boucle tant que l'écran vit ; le
  /// chevron n'est de toute façon affiché que pendant un enregistrement non
  /// verrouillé, donc rien ne s'anime à l'écran le reste du temps.
  ///
  /// Créé dans initState et NON par un initialiseur `late final` : celui-ci
  /// est paresseux, et si l'utilisateur n'enregistre aucun vocal, le premier
  /// accès serait `dispose()` — qui créerait alors un ticker sur un State en
  /// cours de destruction.
  late final AnimationController _lockPulse;
  final _inputCtrl = WhatsappFormattingController();
  final _inputFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  List<Message> _messages = [];
  List<CallRecord> _callsForConv = [];
  List<dynamic> _combined = [];
  bool _loading = true;
  bool _sending = false;

  /// Barre de mise en forme dépliée par le bouton « A » du composeur.
  bool _formatBarOpen = false;

  /// Le champ contient-il quelque chose ? Pilote le bouton rond du composeur,
  /// qui montre le micro quand le champ est vide et l'envoi dès qu'on écrit.
  bool _hasText = false;

  /// Panneau d'emojis déplié par le bouton smiley, à gauche du champ.
  bool _emojiPanelOpen = false;

  /// Doigt posé sur le micro. Distinct de `_recording`, qui ne passe à vrai
  /// qu'une fois l'enregistrement réellement démarré : l'agrandissement doit
  /// répondre à l'appui, pas attendre l'ouverture du fichier audio.
  bool _micHeld = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
  bool _wasBusy = false;
  // _myId reflète TOUJOURS l'utilisateur courant. Un getter (au lieu d'un champ
  // figé au chargement) évite un état périmé/null : si l'auth se charge en
  // différé, l'ancien code laissait _myId = null, ce qui inversait l'alignement
  // des bulles (nos propres messages affichés côté « reçu »).
  String? get _myId {
    try {
      return context.read<AuthController>().user?.id;
    } catch (_) {
      return null;
    }
  }

  // Couleurs theme-aware (mode Nuit).
  bool get _dark => Theme.of(context).brightness == Brightness.dark;

  /// Vrai en thème Noir. Ne sert QUE dans la branche `_dark` des getters
  /// ci-dessous : le mode clair ne passe jamais par ici et reste donc figé.
  bool get _noir => estNoir(context);

  /// Vrai en thème Blanc. Symétrique de [_noir] : n'intervient que dans la
  /// branche CLAIRE, donc le thème Clair d'origine reste figé.
  bool get _blanc => estBlanc(context);

  // En Blanc, l'en-tête est blanc à texte sombre — comme la référence — et non
  // terre cuite à texte blanc.
  Color get _appBarBg => _dark
      ? surfacesOf(context).surface
      : (_blanc ? Colors.white : AlanyaColors.terracotta);
  Color get _onAppBar => _dark
      ? (_noir ? AlanyaColors.noirTexte : AlanyaColors.craie)
      : (_blanc ? AlanyaColors.blancTexte : Colors.white);
  Color get _onAppBarSub => _dark
      ? (_noir ? AlanyaColors.noirTexte2 : AlanyaColors.craie2)
      : (_blanc ? AlanyaColors.blancTexte2 : Colors.white70);
  Color get _composerBg => _dark
      ? surfacesOf(context).surface
      : (_blanc ? Colors.white : AlanyaColors.cream);
  // Les bulles viennent désormais de la ThemeExtension. Les valeurs y ont été
  // relevées sur ce code, pas choisies : Nuit et Clair rendent à l'identique.
  Color get _sentBubbleColor => surfacesOf(context).bulleEnvoyee;
  Color get _recvBubbleColor => surfacesOf(context).bulleRecue;
  Color _bubbleTextColor(bool mine) => mine
      ? surfacesOf(context).texteBulleEnvoyee
      : surfacesOf(context).texteBulleRecue;
  // Le mode clair reste EXACTEMENT ce qu'il était : seules les branches Nuit
  // et Noir varient (cf. helper themed() dans alanya_theme.dart).
  Color get _muted => _dark
      ? (_noir ? AlanyaColors.noirTexte2 : AlanyaColors.craie2)
      : (_blanc ? AlanyaColors.blancTexte2 : Colors.black54);
  Color get _muted45 => _dark
      ? (_noir ? AlanyaColors.noirTexte2 : AlanyaColors.craie2)
      : (_blanc ? AlanyaColors.blancTexte2 : Colors.black45);
  Color get _mutedIcon => _dark
      ? (_noir ? AlanyaColors.noirTexte2 : AlanyaColors.craie2)
      : (_blanc ? AlanyaColors.blancTexte2 : AlanyaColors.grey400);
  Color get _accent => _dark
      ? (_noir ? AlanyaColors.teal : AlanyaColors.terracottaNuit)
      : (_blanc ? AlanyaColors.teal : AlanyaColors.terracotta);
  Color get _accentSoft => _dark
      ? (_noir ? AlanyaColors.teal : AlanyaColors.terracottaNuitLight)
      : (_blanc ? AlanyaColors.teal : AlanyaColors.terracotta);
  Color get _iconNeutral => _dark
      ? (_noir ? AlanyaColors.noirTexte2 : AlanyaColors.craie2)
      : (_blanc ? AlanyaColors.blancTexte2 : AlanyaColors.chocolate);
  Color get _positive => _dark
      ? (_noir ? AlanyaColors.teal : AlanyaColors.indigoLight)
      : AlanyaColors.forest;
  Color get _danger => _dark
      ? (_noir ? AlanyaColors.erreurNoir : AlanyaColors.erreurNuit)
      : Colors.red;
  Color get _hairline => _dark
      ? (_noir ? AlanyaColors.noirLigne : AlanyaColors.ligne)
      : (_blanc ? AlanyaColors.blancLigne : AlanyaColors.sand);
  Color get _cardBg => _dark ? surfacesOf(context).surface : Colors.white;

  /// Fond des pastilles système du fil (date, message éphémère…).
  Color get _pillBg => _dark
      ? surfacesOf(context).surfaceHaute.withValues(alpha: 0.9)
      : Colors.black.withValues(alpha: 0.06);

  /// Fond du bloc de citation dans une bulle reçue. En Nuit, le modèle demande
  /// un creux plus sombre que la bulle ; en clair on garde le sable et son
  /// opacité d'origine, qui diffère selon l'emplacement d'où l'appel vient.
  Color _quoteBgRecv(double lightAlpha) => _dark
      ? surfacesOf(context).fond.withValues(alpha: 0.35)
      : AlanyaColors.sand.withOpacity(lightAlpha);

  /// Bandeau d'enregistrement vocal en cours.
  Color get _recordBg => _dark
      ? AlanyaColors.erreurNuit.withValues(alpha: 0.16)
      : Colors.red.shade50;

  String? _token;
  String _baseUrl = "";
  bool _uploading = false;

  /// Envois de médias en cours ou échoués, indexés par l'identifiant provisoire
  /// du message optimiste correspondant. Voir `envoi_media.dart`.
  final Map<String, EnvoiMedia> _envois = {};

  /// Minuteurs qui bornent l'attente de l'écho du serveur (trames WebSocket
  /// sans accusé). Annulés à la destruction de l'écran, sinon ils réveillent un
  /// `setState` sur un État mort.
  final Map<String, Timer> _attentesEcho = {};
  final _voiceRecorder = VoiceRecorder();
  bool _recording = false;
  DateTime? _recordStarted;
  bool _recordLocked = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  bool _voiceActive = false;
  // Indicateurs temps réel (émission) : "en train d'écrire" / "enregistre".
  late final RealtimeClient _rt;
  Timer? _typingDebounce;
  bool _typingSent = false;
  bool _recordingSent = false;
  // Réception : activité du correspondant.
  bool _peerTyping = false;
  bool _peerRecording = false;
  Timer? _typingTimeout;
  Timer? _recordingTimeout;
  Message? _replyTo;
  Message? _editing; // message en cours d'édition (compose = mode édition)

  // ── Sélection d'un message (interaction long-press façon WhatsApp) ──
  String? _selectedMessageId;
  OverlayEntry? _actionsOverlay;

  // ── Message épinglé (partagé à la conversation) ──
  String? _pinnedMessageId;

  // ── Messages éphémères : minuteur de la conversation (0 = désactivé) ──
  int _disappearingSeconds = 0;

  // ── Recherche dans la conversation ──
  bool _searchMode = false;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<String> _searchResultIds = [];
  int _searchIndex = 0;
  bool _searchLoading = false;
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, ReplyPreview> _replySnapshots = {};
  final _translateService = TranslateService();
  final Map<String, String> _translations = {};
  final Set<String> _translating = {};

  // Lot D — scroll infini (chargement des messages plus anciens).
  bool _loadingOlder = false;
  bool _hasMoreOlder = true;
  bool _loadedOlder = false;

  @override
  void initState() {
    super.initState();
    _lockPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    ChatScreen.activeConvId = widget.convId;
    _load();
    _loadPinned();
    _loadDisappearing();
    _scrollCtrl.addListener(_onScroll);
    // Le basculement micro ↔ envoi écoute le CONTRÔLEUR et non `onChanged` :
    // le texte change aussi sans frappe — mise en forme WhatsApp appliquée à
    // la sélection, insertion d'un emoji, vidage après envoi. `onChanged` ne
    // voit aucun de ces cas et le bouton resterait sur le mauvais symbole.
    _inputCtrl.addListener(_onInputTextChanged);
    final rt = context.read<RealtimeClient>();
    _rt = rt;
    rt.connect();
    _rtSub = rt.events.listen(_onRealtimeEvent);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    // Comme pour les messages : on utilise le serveur temps réel (WebSocket / WebRTC signaling)
    // pas de Timer polling pour les appels, juste event-driven
    context.read<CallController>().addListener(_onCallActivity);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Suit le remplissage du champ pour choisir le symbole du bouton rond.
  ///
  /// `setState` n'est appelé que sur un vrai changement d'état (vide ↔ rempli),
  /// pas à chaque caractère : le listener se déclenche aussi à chaque
  /// déplacement du curseur.
  void _onInputTextChanged() {
    final rempli = _inputCtrl.text.trim().isNotEmpty;
    if (rempli == _hasText) return;
    setState(() => _hasText = rempli);
  }

  /// Insère un emoji à la position du curseur, ou à la fin si le champ n'a
  /// jamais eu le focus (la sélection vaut alors -1).
  void _insereEmoji(String emoji) {
    final texte = _inputCtrl.text;
    final sel = _inputCtrl.selection;
    final debut = sel.start < 0 ? texte.length : sel.start;
    final fin = sel.end < 0 ? texte.length : sel.end;
    _inputCtrl.value = TextEditingValue(
      text: texte.replaceRange(debut, fin, emoji),
      selection: TextSelection.collapsed(offset: debut + emoji.length),
    );
  }

  // ── Indicateurs temps réel : émission (débounce + cycle de vie) ──
  void _emitTyping(bool on) {
    if (on == _typingSent) return;
    _typingSent = on;
    _rt.sendTyping(widget.convId, on);
  }

  void _emitRecording(bool on) {
    if (on == _recordingSent) return;
    _recordingSent = on;
    _rt.sendRecording(widget.convId, on);
  }

  void _onInputChanged(String text) {
    // typing_start dès 3 caractères ; typing_stop après ~1,5 s d'inactivité.
    if (text.trim().length >= 3) {
      _emitTyping(true);
      _typingDebounce?.cancel();
      _typingDebounce =
          Timer(const Duration(milliseconds: 1500), () => _emitTyping(false));
    } else {
      _typingDebounce?.cancel();
      _emitTyping(false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App en arrière-plan → on coupe les indicateurs (évite un état figé chez
    // le correspondant). Au retour, on ré-émet si un enregistrement est en cours.
    if (state != AppLifecycleState.resumed) {
      _typingDebounce?.cancel();
      _emitTyping(false);
      _emitRecording(false);
    } else {
      if (_recording) _emitRecording(true);
      // Un appel a pu se terminer pendant que l'app était en arrière-plan :
      // l'événement WebSocket est alors passé sans que personne l'entende, et
      // il ne sera pas rejoué. On rattrape au retour.
      _rafraichitAppels();
    }
  }

  void _onCallActivity() {
    // Fin d'appel local (busy->!busy) : serveur va émettre call_state, on recharge via WS
    // + reload immédiat au cas où WS a un léger délai
    try {
      final busy = context.read<CallController>().isBusy;
      if (_wasBusy && !busy) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _loadCalls();
        });
      }
      _wasBusy = busy;
    } catch (_) {}
  }

  @override
  void dispose() {
    ChatScreen.activeConvId = null;
    WidgetsBinding.instance.removeObserver(this);
    _typingDebounce?.cancel();
    _typingTimeout?.cancel();
    _recordingTimeout?.cancel();
    _emitTyping(false);
    _emitRecording(false);
    _pollTimer?.cancel();
    _recordTimer?.cancel();
    // Un minuteur d'attente d'écho qui survit à l'écran appellerait `setState`
    // sur un État détruit — l'exception classique après avoir quitté une
    // conversation pendant un envoi.
    for (final t in _attentesEcho.values) {
      t.cancel();
    }
    _attentesEcho.clear();
    _rtSub?.cancel();
    try {
      context.read<CallController>().removeListener(_onCallActivity);
    } catch (_) {}
    _lockPulse.dispose();
    _voiceRecorder.cancel();
    _translateService.dispose();
    InlineAudioPlayer.stop();
    _inputCtrl.removeListener(_onInputTextChanged);
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _actionsOverlay?.remove();
    super.dispose();
  }

  // ══════════════════════════════════════════════
  // RECHERCHE DANS LA CONVERSATION
  // ══════════════════════════════════════════════
  void _openSearch() {
    setState(() {
      _searchMode = true;
      _searchResultIds = [];
      _searchIndex = 0;
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _searchMode = false;
      _searchResultIds = [];
      _searchLoading = false;
    });
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResultIds = [];
        _searchLoading = false;
      });
      return;
    }
    setState(() => _searchLoading = true);
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    try {
      final results = await context
          .read<ChatRepository>()
          .searchMessages(widget.convId, query);
      if (!mounted) return;
      final ids =
          results.map((r) => r["id"] as String?).whereType<String>().toList();
      setState(() {
        _searchResultIds = ids;
        _searchIndex = 0;
        _searchLoading = false;
      });
      if (ids.isNotEmpty) _scrollToMessage(ids.first);
    } catch (_) {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _searchNav(int delta) {
    if (_searchResultIds.isEmpty) return;
    final next =
        (_searchIndex + delta).clamp(0, _searchResultIds.length - 1).toInt();
    if (next == _searchIndex) return;
    setState(() => _searchIndex = next);
    _scrollToMessage(_searchResultIds[next]);
  }

  // ══════════════════════════════════════════════
  // REALTIME
  // ══════════════════════════════════════════════
  void _onRealtimeEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final type = e["type"];
    if (type == "message") {
      final data = e["message"] as Map<String, dynamic>?;
      if (data == null || data["convId"] != widget.convId) return;
      final msg = Message.fromJson(data);
      _cacheMsg(msg);
      final tempId = e["tempId"] as String?;
      setState(() {
        final idx =
            tempId != null ? _messages.indexWhere((m) => m.id == tempId) : -1;
        if (idx >= 0) {
          _messages[idx] = msg;
        } else if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        // L'écho est la seule preuve que le message existe côté serveur : c'est
        // ici, et nulle part avant, que l'envoi cesse d'être « en cours ».
        if (tempId != null) {
          _attentesEcho.remove(tempId)?.cancel();
          _envois.remove(tempId);
        }
        _rebuildCombined();
      });
      if (msg.senderId != _myId) {
        _markReadRemote();
        // Conversation ouverte : aucune notification système n'est affichée,
        // le son est donc le seul signal d'arrivée. Respecte le réglage
        // « Notifications de messages ».
        if (NotificationSettings.instance.messagesOn) {
          RingtoneService.instance.playMessageReceived();
        }
      }
      _scrollToBottom();
    } else if (type == "read") {
      if (e["convId"] != widget.convId) return;
      setState(() {
        _messages = _messages
            .map((m) => m.senderId == _myId && m.status != "READ"
                ? Message(
                    id: m.id,
                    convId: m.convId,
                    senderId: m.senderId,
                    content: m.content,
                    type: m.type,
                    status: "READ",
                    replyToId: m.replyToId,
                    replyTo: m.replyTo,
                    deletedAt: m.deletedAt,
                    editedAt: m.editedAt,
                    media: m.media,
                    createdAt: m.createdAt,
                    reactions: m.reactions,
                    starred: m.starred,
                    expiresAt: m.expiresAt)
                : m)
            .toList();
      });
    } else if (type == "message_status") {
      final messageId = e["messageId"] as String?;
      final newStatus = e["status"] as String?;
      if (messageId == null || newStatus == null) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == messageId &&
                    _statusRank(newStatus) > _statusRank(m.status)
                ? Message(
                    id: m.id,
                    convId: m.convId,
                    senderId: m.senderId,
                    content: m.content,
                    type: m.type,
                    status: newStatus,
                    replyToId: m.replyToId,
                    replyTo: m.replyTo,
                    deletedAt: m.deletedAt,
                    editedAt: m.editedAt,
                    media: m.media,
                    createdAt: m.createdAt,
                    reactions: m.reactions,
                    starred: m.starred,
                    expiresAt: m.expiresAt)
                : m)
            .toList();
      });
    } else if (type == "message_deleted") {
      final messageId = e["messageId"] as String?;
      final scope = e["scope"] as String? ?? "me";
      if (messageId == null || e["convId"] != widget.convId) return;
      setState(() {
        if (scope == "me") {
          _messages = _messages.where((m) => m.id != messageId).toList();
        } else {
          _messages = _messages
              .map((m) => m.id == messageId
                  ? Message(
                      id: m.id,
                      convId: m.convId,
                      senderId: m.senderId,
                      content: null,
                      type: m.type,
                      status: m.status,
                      replyToId: m.replyToId,
                      replyTo: m.replyTo,
                      deletedAt: DateTime.now(),
                      media: const [],
                      createdAt: m.createdAt)
                  : m)
              .toList();
        }
      });
    } else if (type == "typing") {
      if (e["convId"] != widget.convId) return;
      _onPeerActivity(
          typing: e["isTyping"] == true, uid: e["userId"] as String?);
    } else if (type == "recording") {
      if (e["convId"] != widget.convId) return;
      _onPeerActivity(
          recording: e["isRecording"] == true, uid: e["userId"] as String?);
    } else if (type == "reaction") {
      if (e["convId"] != widget.convId) return;
      final messageId = e["messageId"] as String?;
      final uid = e["userId"] as String?;
      final emoji = e["emoji"] as String?; // null = retrait
      if (messageId == null || uid == null) return;
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx < 0) return;
      setState(() {
        final m = _messages[idx];
        final updated = m.reactions.where((r) => r.userId != uid).toList();
        if (emoji != null && emoji.isNotEmpty) {
          updated.add(MessageReaction(userId: uid, emoji: emoji));
        }
        m.reactions = updated;
      });
    } else if (type == "message_edited") {
      if (e["convId"] != widget.convId) return;
      final messageId = e["messageId"] as String?;
      final content = e["content"] as String?;
      if (messageId == null || content == null) return;
      final editedAtStr = e["editedAt"] as String?;
      final editedAt =
          (editedAtStr != null ? DateTime.tryParse(editedAtStr) : null) ??
              DateTime.now();
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx < 0) return;
      setState(() {
        _messages[idx] = _withEdited(_messages[idx], content, editedAt);
      });
    } else if (type == "message_pinned") {
      if (e["convId"] != widget.convId) return;
      setState(() => _pinnedMessageId = e["messageId"] as String?);
    } else if (type == "disappearing_updated") {
      if (e["convId"] != widget.convId) return;
      setState(
          () => _disappearingSeconds = (e["seconds"] as num?)?.toInt() ?? 0);
    } else if (type == "call_ended") {
      // Le serveur pousse l'appel COMPLET : on l'insère, sans rien recharger.
      final brut = e["call"];
      if (brut is Map) {
        _integreAppel(CallRecord.fromJson(Map<String, dynamic>.from(brut)));
      }
    } else if (type == "call_state") {
      // Repli : un serveur qui n'envoie pas encore `call_ended` ne signale que
      // le changement d'état, il faut alors aller chercher l'appel. Le garde de
      // `_rafraichitAppels` évite de doubler l'insertion directe quand les deux
      // arrivent — `_integreAppel` le réarme.
      final callId = e["callId"] as String?;
      if (callId != null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _rafraichitAppels();
        });
      }
    } else if (type == "incoming_call") {
      // Nouvel appel entrant pendant que le chat est ouvert
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _loadCalls();
      });
    } else if (type == "ws_connected") {
      // Reconnexion : ce qui s'est produit pendant la coupure n'a jamais été
      // reçu, et un événement WebSocket ne se rejoue pas. On rattrape.
      _rafraichitAppels();
    }
  }

  // ── Réception : indicateur d'activité du correspondant ──
  void _onPeerActivity({bool? typing, bool? recording, String? uid}) {
    if (uid != null && uid == _myId) return; // ignore un éventuel écho de soi
    final appearing = !_peerTyping && !_peerRecording;
    if (typing != null) {
      _typingTimeout?.cancel();
      if (typing) {
        // Filet de sécurité : efface l'indicateur si aucun "stop" n'arrive.
        _typingTimeout = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _peerTyping = false);
        });
      }
      if (_peerTyping != typing) setState(() => _peerTyping = typing);
    }
    if (recording != null) {
      _recordingTimeout?.cancel();
      if (recording) {
        _recordingTimeout = Timer(const Duration(seconds: 12), () {
          if (mounted) setState(() => _peerRecording = false);
        });
      }
      if (_peerRecording != recording)
        setState(() => _peerRecording = recording);
    }
    // Aucun son ici : l'indicateur d'activité est une information visuelle.
    // Faire sonner le destinataire pendant que l'autre tape le prévenait d'un
    // message qui n'existait pas encore. Le son est déclenché à la réception
    // du message, dans _onRealtimeEvent.
  }

  void _markReadRemote() {
    final rt = context.read<RealtimeClient>();
    if (rt.connected) {
      rt.markRead(widget.convId);
    } else {
      context.read<ChatRepository>().markRead(widget.convId);
    }
  }

  Future<void> _load() async {
    // _myId est désormais un getter (toujours à jour) — plus besoin de le figer ici.
    _baseUrl = context.read<ApiClient>().baseUrl;
    initMediaIntegration(_baseUrl);
    _token = await context.read<TokenStorage>().accessToken;
    final cached = await MessageCache.getConv(widget.convId);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
        _rebuildCombined();
        _loading = false;
      });
      for (final m in _messages) {
        _cacheMsg(m);
      }
      _scrollToBottom(immediat: true);
    }
    try {
      final repo = context.read<ChatRepository>();
      final msgs = await repo.getMessages(widget.convId);
      if (!mounted) return;
      final reversed = msgs.reversed.toList();
      await MessageCache.putConv(widget.convId, reversed);
      setState(() {
        _messages = reversed;
        _rebuildCombined();
        _loading = false;
      });
      for (final m in _messages) {
        _cacheMsg(m);
      }
      _markReadRemote();
      _scrollToBottom(immediat: true);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    // Charge aussi les appels de cette conversation pour les afficher façon WhatsApp
    _loadCalls();
  }

  // Scroll infini : proche du haut → charge les messages plus anciens.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    // ⚠️ La liste est INVERSÉE : le plus ancien n'est plus au décalage 0, il est
    // à `maxScrollExtent`. Garder l'ancien test (`pixels <= 240`) déclencherait
    // le chargement de l'historique quand on est en bas, c'est-à-dire sur les
    // messages les PLUS RÉCENTS — et jamais quand on remonte le fil.
    final p = _scrollCtrl.position;
    if (p.pixels >= p.maxScrollExtent - 240 &&
        !_loadingOlder &&
        _hasMoreOlder) {
      _loadOlder();
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMoreOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final cursor = _messages.first.id;
    try {
      final older = await context
          .read<ChatRepository>()
          .getMessages(widget.convId, cursor: cursor);
      if (!mounted) return;
      if (older.isEmpty) {
        _hasMoreOlder = false;
      } else {
        final newMsgs = older.reversed.toList();
        final before =
            _scrollCtrl.hasClients ? _scrollCtrl.position.maxScrollExtent : 0.0;
        _loadedOlder = true;
        setState(() {
          _messages = [...newMsgs, ..._messages];
          _rebuildCombined();
        });
        for (final m in newMsgs) {
          _cacheMsg(m);
          MessageCache.upsert(m, widget.convId);
        }
        // Préserve la position visuelle après l'ajout en tête (pas de saut).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollCtrl.hasClients) return;
          final after = _scrollCtrl.position.maxScrollExtent;
          _scrollCtrl.jumpTo(_scrollCtrl.position.pixels + (after - before));
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _poll() async {
    if (!mounted || _loading) return;
    // Ne pas écraser l'historique chargé via le scroll infini.
    if (_loadingOlder || _loadedOlder) return;
    if (context.read<RealtimeClient>().connected) return;
    try {
      final repo = context.read<ChatRepository>();
      final latest = (await repo.getMessages(widget.convId)).reversed.toList();
      if (!mounted) return;
      if (_signature(latest) == _signature(_messages)) return;
      final hadMore = latest.length > _messages.length;
      final atBottom = !_scrollCtrl.hasClients ||
          _scrollCtrl.position.pixels >=
              _scrollCtrl.position.maxScrollExtent - 60;
      setState(() {
        _messages = latest;
        _rebuildCombined();
      });
      for (final m in latest) {
        _cacheMsg(m);
      }
      if (hadMore) repo.markRead(widget.convId);
      if (hadMore && atBottom) _scrollToBottom();
    } catch (_) {}
  }

  String _signature(List<Message> msgs) =>
      msgs.map((m) => "${m.id}:${m.status}").join("|");

  // ══════════════════════════════════════════════
  // APPELS DANS LE FIL (WhatsApp-like)
  // ══════════════════════════════════════════════
  DateTime _dateOfCombined(dynamic item) {
    if (item is Message) return item.createdAt;
    if (item is CallRecord) return item.startedAt;
    if (item is GroupeMedias) return item.date;
    return DateTime.now();
  }

  void _rebuildCombined() {
    final all = <dynamic>[..._messages, ..._callsForConv];
    all.sort((a, b) => _dateOfCombined(a).compareTo(_dateOfCombined(b)));
    final avant = _combined.length;
    _combined = _regroupeMedias(all);
    // 🔬 Trace temporaire : un changement du NOMBRE d'éléments déplace tout ce
    // qui suit dans une liste ancrée en haut. C'est l'un des deux suspects.
    if (avant != _combined.length) {
      debugPrint(
          "[DEFIL] liste recomposée — $avant → ${_combined.length} éléments");
    }
  }

  /// Regroupe en UNE grille les messages de médias consécutifs d'un même
  /// expéditeur.
  ///
  /// 🔴 **POURQUOI C'EST INDISPENSABLE, et pas un embellissement** : le client
  /// web n'envoie QU'UN média par message (`websocket-service.ts` n'a pas de
  /// `mediaIds`), et l'application de l'équipe non plus. Cinq photos envoyées
  /// depuis le web arrivent donc en CINQ messages : la grille existante, qui ne
  /// regroupe que les médias d'un même message, ne pouvait rien y faire, et le
  /// fil affichait cinq bulles empilées. C'est le défaut « réception de
  /// plusieurs photos en groupe » signalé par le user.
  ///
  /// Sert aussi à nos propres envois : au-delà de 10 médias, l'envoi est
  /// découpé en plusieurs messages (plafond serveur) — le regroupement les
  /// réunit visuellement.
  ///
  /// ⚠️ **Ce qui est volontairement EXCLU du regroupement**, parce que le
  /// message porte alors quelque chose que la grille ne saurait pas montrer :
  /// une légende (elle appartient à SON message), une réaction, une étoile, une
  /// citation, un message supprimé, et un envoi encore en cours. Mieux vaut une
  /// bulle seule qu'une information effacée par un regroupement.
  List<dynamic> _regroupeMedias(List<dynamic> items) {
    bool groupable(dynamic x) {
      if (x is! Message) return false;
      if (x.media.isEmpty) return false;
      if (x.isDeleted) return false;
      if ((x.content ?? '').isNotEmpty) return false;
      if (x.replyToId != null) return false;
      if (x.reactions.isNotEmpty) return false;
      if (x.starred) return false;
      if (_envois.containsKey(x.id)) return false;
      final t = _typeEffectif(x);
      return t == 'IMAGE' || t == 'VIDEO';
    }

    final sortie = <dynamic>[];
    var i = 0;
    while (i < items.length) {
      final courant = items[i];
      if (!groupable(courant)) {
        sortie.add(courant);
        i++;
        continue;
      }
      final lot = <Message>[courant as Message];
      var j = i + 1;
      while (j < items.length && lot.length < 10) {
        final suivant = items[j];
        if (!groupable(suivant)) break;
        final msg = suivant as Message;
        if (msg.senderId != lot.last.senderId) break;
        // 60 s : c'est le temps qu'un envoi multiple met à s'égrener, pas celui
        // d'une conversation. Au-delà, deux photos sont deux propos distincts et
        // les fondre effacerait cette distinction.
        if (msg.createdAt.difference(lot.last.createdAt).inSeconds > 60) break;
        lot.add(msg);
        j++;
      }
      if (lot.length > 1) {
        sortie.add(GroupeMedias(lot));
      } else {
        sortie.add(courant);
      }
      i = j;
    }
    return sortie;
  }

  /// Recharge les appels de cette conversation : le cache pour l'affichage
  /// immédiat, puis le serveur qui fait autorité.
  ///
  /// ⚠️ La version précédente n'interrogeait le serveur QUE si le cache était
  /// vide, donc ne pouvait jamais découvrir un appel nouveau : un seul appel en
  /// cache suffisait à ce que tous les rechargements suivants relisent ce même
  /// cache. L'événement WebSocket arrivait bien, mais ne changeait rien.
  Future<void> _loadCalls() async {
    // Dépôt capturé AVANT tout await : le lire après reviendrait à toucher un
    // BuildContext qui peut avoir été démonté entre-temps.
    final repo = context.read<CallsRepository>();
    try {
      final caches = await CallCache.getAll();
      if (caches.isNotEmpty && mounted) _appliqueCalls(caches);
    } catch (_) {}
    try {
      // Endpoint dédié à CETTE conversation, au lieu des 50 derniers appels
      // toutes conversations confondues qu'il fallait ensuite filtrer. Au-delà
      // de ces 50, les appels de la conversation ouverte tombaient hors de la
      // fenêtre et disparaissaient du fil sans rien indiquer.
      final calls = await repo.forConversation(widget.convId);
      if (!mounted) return;
      _appliqueCalls(calls);
      // ⚠️ PAS de CallCache.putAll ici : ce cache porte l'historique GLOBAL,
      // que l'écran Appels relit tel quel. Y écrire les appels d'une seule
      // conversation effacerait tous les autres — `putAll` commence par vider
      // la table.
    } catch (_) {
      // Repli : un serveur sans l'endpoint dédié répond 404. On repasse par
      // l'historique global, filtré comme avant.
      try {
        final calls = await repo.history();
        if (!mounted) return;
        _appliqueCalls(calls);
      } catch (_) {}
    }
  }

  void _appliqueCalls(List<CallRecord> calls) {
    final filtered = calls.where((c) => c.convId == widget.convId).toList();
    if (!mounted) return;
    setState(() {
      _callsForConv = filtered;
      _rebuildCombined();
    });
  }

  /// Insère (ou remplace) un appel poussé par le serveur, sans requête.
  ///
  /// Remplace par le même identifiant plutôt que d'ajouter : un appel passe par
  /// plusieurs états, et le même arriverait deux fois dans le fil.
  ///
  /// Réarme le garde anti-rafale : l'appel étant déjà à jour, le
  /// `call_state` qui l'accompagne n'a plus rien à aller chercher.
  void _integreAppel(CallRecord c) {
    if (c.convId != widget.convId) return;
    _dernierRafraichissementAppels = DateTime.now();
    final liste = List<CallRecord>.from(_callsForConv);
    final i = liste.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      liste[i] = c;
    } else {
      liste.add(c);
    }
    if (!mounted) return;
    setState(() {
      _callsForConv = liste;
      _rebuildCombined();
    });
  }

  /// Voir l'homologue dans la liste des conversations : garde anti-rafale pour
  /// les rafraîchissements automatiques, qui se déclenchent souvent ensemble.
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

  // ── Formalisme centralisé (lib/core/call_status.dart) ──
  // Respecte : MISSED=entrant sans réponse, REJECTED=entrant refusé par moi,
  // NO_ANSWER/Refusé=sortant non décroché/rejeté par autre, BUSY=occupé
  // Nuance A->B : B ne décroche pas => A "Appel sans réponse", B "Appel manqué"
  //               B rejette => A "Appel refusé", B "Appel rejeté"
  String _preciseCallStatus(CallRecord c) =>
      CallStatusFormalisme.preciseLabel(c);

  String _callTitleInChat(CallRecord c) => CallStatusFormalisme.titleInChat(c);

  String _callDetailInChat(CallRecord c) =>
      CallStatusFormalisme.detailInChat(c);

  IconData _callIconFor(CallRecord c) => CallStatusFormalisme.iconFor(c);

  Color _callColorFor(CallRecord c) =>
      CallStatusFormalisme.colorFor(c, danger: _danger, positive: _positive);

  String _formatCallDateTime(DateTime dt) =>
      CallStatusFormalisme.formatDateTime(dt);

  String _formatCallDuration(int? sec) =>
      CallStatusFormalisme.formatDuration(sec);

  Widget _callBubbleInChat(CallRecord c) {
    final title = _callTitleInChat(c); // ex: Appel vocal entrant / sortant
    final detail =
        _callDetailInChat(c); // Rejeté / Sans réponse / Répondu / Occupé
    final icon = _callIconFor(c);
    final color = _callColorFor(c); // rouge / vert / bleu selon demande
    final time = _time(c.startedAt); // HH:mm comme dans l'image
    final dur = _formatCallDuration(c.durationSec);
    // De quel côté sortir la bulle : décidé sur `callerId`, le fait brut, et
    // non sur le booléen `isOutgoing`. Les deux disent la même chose tant que
    // le serveur est juste, mais `callerId` se vérifie ici même — une bulle du
    // mauvais côté est une erreur qu'on ne peut pas rattraper à la lecture.
    // `emisPar` retombe sur `isOutgoing` si le serveur n'envoie pas encore
    // `callerId`.
    final mine = c.emisPar(_myId);

    // Bulle fine type WhatsApp (demande : épaisseur trop grosse, on réduit)
    // Fond conservé d'origine (_cardBg), alignée gauche/droite
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onTap: () => _showCallChoice(c),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(mine ? 10 : 0),
          topRight: Radius.circular(mine ? 0 : 10),
          bottomLeft: const Radius.circular(10),
          bottomRight: const Radius.circular(10),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(mine ? 10 : 0),
              topRight: Radius.circular(mine ? 0 : 10),
              bottomLeft: const Radius.circular(10),
              bottomRight: const Radius.circular(10),
            ),
            border: Border.all(color: _hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.call, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _dark ? AlanyaColors.craie : AlanyaColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 10, color: color),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            dur.isNotEmpty
                                ? "$detail · $time · $dur"
                                : "$detail · $time",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCallChoice(CallRecord c) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                c.isGroup
                    ? "Rappeler le groupe ?"
                    : "Rappeler ${widget.title} ?",
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.call, color: _positive),
              title: const Text("Appel audio"),
              onTap: () => Navigator.pop(ctx, "AUDIO"),
            ),
            ListTile(
              leading: Icon(Icons.videocam, color: _positive),
              title: const Text("Appel vidéo"),
              onTap: () => Navigator.pop(ctx, "VIDEO"),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice != null) {
      _startCall(choice);
    }
  }

  bool _needsDateSeparatorCombined(int index) {
    if (index == 0) return true;
    final prev = _dateOfCombined(_combined[index - 1]).toLocal();
    final curr = _dateOfCombined(_combined[index]).toLocal();
    return prev.year != curr.year ||
        prev.month != curr.month ||
        prev.day != curr.day;
  }

  // ══════════════════════════════════════════════
  // SEND
  // ══════════════════════════════════════════════
  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    // Mode édition : on modifie le message au lieu d'en envoyer un nouveau.
    if (_editing != null) {
      _submitEdit(text);
      return;
    }
    _typingDebounce?.cancel();
    _emitTyping(false); // on arrête l'indicateur dès l'envoi
    final rt = context.read<RealtimeClient>();
    final replyId = _replyTo?.id;
    if (rt.connected) {
      final tempId = "tmp-${DateTime.now().microsecondsSinceEpoch}";
      final replyMsg = _replyTo;
      final replySnapshot = replyMsg != null
          ? ReplyPreview(
              id: replyMsg.id,
              senderId: replyMsg.senderId,
              type: replyMsg.type,
              content: replyMsg.isDeleted ? null : replyMsg.content,
              isDeleted: replyMsg.isDeleted)
          : null;
      final optimistic = Message(
          id: tempId,
          convId: widget.convId,
          senderId: _myId ?? "",
          content: text,
          type: "TEXT",
          status: "SENT",
          replyToId: replyId,
          replyTo: replySnapshot,
          media: const [],
          createdAt: DateTime.now());
      setState(() {
        _messages = [..._messages, optimistic];
        _rebuildCombined();
        _replyTo = null;
      });
      _inputCtrl.clear();
      rt.sendMessage(widget.convId, text, tempId, replyToId: replyId);
      _scrollToBottom();
      return;
    }
    setState(() {
      _sending = true;
    });
    try {
      final msg = await context
          .read<ChatRepository>()
          .sendText(widget.convId, text, replyToId: replyId);
      _cacheMsg(msg);
      _inputCtrl.clear();
      setState(() {
        _messages = [..._messages, msg];
        _rebuildCombined();
        _replyTo = null;
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      final tempId = "out-${DateTime.now().microsecondsSinceEpoch}";
      final optimistic = Message(
          id: tempId,
          convId: widget.convId,
          senderId: _myId ?? "",
          content: text,
          type: "TEXT",
          status: "PENDING",
          replyToId: replyId,
          replyTo: null,
          media: const [],
          createdAt: DateTime.now());
      _cacheMsg(optimistic);
      _inputCtrl.clear();
      setState(() {
        _messages = [..._messages, optimistic];
        _rebuildCombined();
        _replyTo = null;
      });
      _scrollToBottom();
      await context.read<Outbox>().enqueue(
          tempId: tempId,
          convId: widget.convId,
          content: text,
          replyToId: replyId);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setReplyTo(Message m) {
    setState(() => _replyTo = m);
    _inputFocus.requestFocus();
  }

  // ── Édition d'un message ──
  Message _withEdited(Message m, String content, DateTime editedAt) => Message(
      id: m.id,
      convId: m.convId,
      senderId: m.senderId,
      content: content,
      type: m.type,
      status: m.status,
      replyToId: m.replyToId,
      replyTo: m.replyTo,
      deletedAt: m.deletedAt,
      editedAt: editedAt,
      media: m.media,
      createdAt: m.createdAt,
      reactions: m.reactions,
      starred: m.starred,
      expiresAt: m.expiresAt);

  void _startEdit(Message m) {
    setState(() {
      _editing = m;
      _replyTo = null;
    });
    _inputCtrl.text = m.content ?? '';
    _inputCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputCtrl.text.length));
    // Ouvre le clavier sur le champ (sinon « rien ne se passe » à l'écran).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  void _cancelEdit() {
    setState(() => _editing = null);
    _inputCtrl.clear();
  }

  void _submitEdit(String text) {
    final m = _editing;
    if (m == null) return;
    final rt = context.read<RealtimeClient>();
    if (rt.connected) {
      rt.editMessage(m.id, text);
    } else {
      context
          .read<ChatRepository>()
          .editMessage(widget.convId, m.id, text)
          .catchError((_) {});
    }
    setState(() {
      final idx = _messages.indexWhere((x) => x.id == m.id);
      if (idx >= 0)
        _messages[idx] = _withEdited(_messages[idx], text, DateTime.now());
      _editing = null;
    });
    _inputCtrl.clear();
  }

  // ══════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════
  Widget _statusTicks(String status, Color baseColor) {
    if (status == "PENDING")
      return Icon(Icons.access_time, size: 13, color: baseColor);
    if (status == "READ")
      return const Icon(Icons.done_all, size: 15, color: AlanyaColors.tickRead);
    if (status == "DELIVERED")
      return Icon(Icons.done_all, size: 15, color: baseColor);
    return Icon(Icons.done, size: 15, color: baseColor);
  }

  int _statusRank(String s) {
    switch (s) {
      case "READ":
        return 2;
      case "DELIVERED":
        return 1;
      default:
        return 0;
    }
  }

  Widget _timestampRow(Message m, bool mine, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (m.expiresAt != null) ...[
        Icon(Icons.timer_outlined, size: 12, color: color),
        const SizedBox(width: 4),
      ],
      if (m.starred) ...[
        Icon(Icons.star, size: 12, color: color),
        const SizedBox(width: 4),
      ],
      if (m.editedAt != null) ...[
        Text("modifié",
            style: TextStyle(
                fontSize: 10, fontStyle: FontStyle.italic, color: color)),
        const SizedBox(width: 4),
      ],
      Text(_time(m.createdAt), style: TextStyle(fontSize: 10, color: color)),
      if (mine) ...[const SizedBox(width: 4), _statusTicks(m.status, color)],
    ]);
  }

  Message? _findMessage(String? id) {
    if (id == null) return null;
    try {
      return _messages.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  void _cacheMsg(Message m) {
    _replySnapshots[m.id] = ReplyPreview(
        id: m.id,
        senderId: m.senderId,
        type: m.type,
        content: m.isDeleted ? null : m.content,
        isDeleted: m.isDeleted);
  }

  ReplyPreview? _resolveReply(Message m) {
    if (m.replyTo != null) return m.replyTo;
    if (m.replyToId == null) return null;
    final cached = _replySnapshots[m.replyToId];
    if (cached != null) return cached;
    final live = _findMessage(m.replyToId);
    if (live != null) {
      _cacheMsg(live);
      return _replySnapshots[live.id];
    }
    return null;
  }

  Future<void> _scrollToMessage(String id) async {
    int foundIdx = _messages.indexWhere((m) => m.id == id);
    if (foundIdx < 0) {
      int attempts = 0;
      while (attempts < 10) {
        attempts++;
        try {
          final cursor = _messages.isNotEmpty ? _messages.first.id : null;
          if (cursor == null) break;
          final older = await context
              .read<ChatRepository>()
              .getMessages(widget.convId, cursor: cursor);
          if (older.isEmpty) break;
          final newMsgs = older.reversed.toList();
          setState(() => _messages = [...newMsgs, ..._messages]);
          for (final m in newMsgs) {
            _cacheMsg(m);
          }
          foundIdx = _messages.indexWhere((m) => m.id == id);
          if (foundIdx >= 0) break;
        } catch (_) {
          break;
        }
      }
    }
    if (foundIdx < 0) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Message introuvable"),
            duration: Duration(seconds: 2)));
      return;
    }
    if (!_scrollCtrl.hasClients) return;

    /*
     * 🐛 **SAUT À L'OPPOSÉ DE LA CIBLE** (signalé sur device le 17/08/2026,
     * après l'inversion du fil). Deux défauts, corrigés ensemble.
     *
     * 1. LE SENS. L'estimation valait `foundIdx / _messages.length`, c'est-à-dire
     *    « à quelle fraction du DÉBUT se trouve ce message ». Depuis que la
     *    liste est inversée, le décalage 0 est le message le plus RÉCENT et
     *    `maxScrollExtent` le plus ancien : ce rapport envoyait donc à l'exact
     *    opposé. Et comme on atterrissait loin de la cible, sa bulle n'était
     *    jamais construite — sa clé restait vide, `ensureVisible` ne
     *    s'exécutait pas, et RIEN n'était surligné. Le second symptôme
     *    découlait du premier.
     *
     * 2. LA LISTE DE RÉFÉRENCE. Le rapport se calculait sur `_messages`, alors
     *    que ce qui est affiché est `_combined` : il contient aussi les appels,
     *    et le regroupement des médias fond plusieurs messages en UN élément.
     *    Deux longueurs différentes donnaient une estimation fausse même avant
     *    l'inversion — d'autant plus fausse que la conversation contient de
     *    photos et d'appels.
     */
    var indexAffiche = -1;
    for (var i = 0; i < _combined.length; i++) {
      final item = _combined[i];
      if (item is Message && item.id == id) {
        indexAffiche = i;
        break;
      }
      // Le message peut avoir été absorbé par une grille : c'est l'élément
      // GROUPE qu'il faut alors viser, puisque c'est lui qui est à l'écran.
      if (item is GroupeMedias && item.messages.any((m) => m.id == id)) {
        indexAffiche = i;
        break;
      }
    }
    if (indexAffiche < 0) return;

    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    // Position DE LECTURE : l'élément 0 de `_combined` est le plus ancien, donc
    // le dernier affiché — près de `maxScrollExtent`.
    final rangAffiche = _combined.length - 1 - indexAffiche;
    final ratio = _combined.isEmpty ? 0.0 : rangAffiche / _combined.length;
    final estimatedOffset = (ratio * maxScroll).clamp(0.0, maxScroll);
    _scrollCtrl.jumpTo(estimatedOffset);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    var key = _messageKeys[id];
    var ctx = key?.currentContext;
    if (ctx == null) {
      _scrollCtrl.jumpTo((estimatedOffset + 200).clamp(0.0, maxScroll));
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      key = _messageKeys[id];
      ctx = key?.currentContext;
    }
    if (ctx != null) {
      // ⚠️ `alignment` se compte depuis le bord de TÊTE du défilement, qui est
      // désormais le BAS : 0.3 plaçait le message près du bas de l'écran au
      // lieu du haut. 0.5 le centre, et cette valeur a le mérite d'être
      // indifférente au sens de lecture.
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5);
      _highlightMessage(id);
    } else {
      _scrollCtrl.animateTo(estimatedOffset,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      _highlightMessage(id);
    }
  }

  void _highlightMessage(String id) {
    setState(() => _highlightedMessageId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightedMessageId == id)
        setState(() => _highlightedMessageId = null);
    });
  }

  /// Texte de la citation d'une réponse.
  ///
  /// Les marqueurs de mise en forme sont retirés : la citation tient sur une
  /// ligne et n'applique pas les styles, or y laisser `*coucou*` afficherait la
  /// mécanique au lieu du message. WhatsApp procède de même.
  String _replyPreviewText(Message? original, ReplyPreview? snapshot) {
    if (snapshot != null) {
      if (snapshot.isDeleted) return tr(context, 'message_deleted');
      // ⚠️ Le libellé AVANT le contenu : un CONTACT ou une LOCATION porte du
      // JSON dans `content`, et cette citation tient sur une ligne.
      final structure = apercuStructure(snapshot.type, snapshot.content);
      if (structure != null) return structure;
      if (snapshot.content != null)
        return sansMarqueursWhatsApp(snapshot.content!);
      return _typeLabel(snapshot.type);
    }
    if (original == null) return '...';
    if (original.isDeleted) return tr(context, 'message_deleted');
    final structure = apercuStructure(original.type, original.content);
    if (structure != null) return structure;
    if (original.content != null)
      return sansMarqueursWhatsApp(original.content!);
    if (original.media.isNotEmpty)
      return original.media.first.filename ?? 'Fichier';
    return _typeLabel(original.type);
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'IMAGE':
        return 'Photo';
      case 'AUDIO':
        return 'Message vocal';
      case 'VIDEO':
        return 'Vidéo';
      case 'FILE':
        return 'Fichier';
      case 'CONTACT':
        return 'Contact';
      case 'LOCATION':
        return 'Position';
      default:
        return '[$type]';
    }
  }

  String _replySenderName(Message? original, ReplyPreview? snapshot) {
    final senderId = snapshot?.senderId ?? original?.senderId;
    if (senderId == null) return tr(context, 'reply_to');
    if (senderId == _myId) return tr(context, 'you');
    return widget.memberNames[senderId] ?? tr(context, 'reply_to');
  }

  // ══════════════════════════════════════════════
  // REPLY PREVIEW HEADER (WhatsApp style)
  // ══════════════════════════════════════════════
  Widget _replyPreviewHeader(Message m, bool mine) {
    final snapshot = _resolveReply(m);
    final original = _findMessage(m.replyToId);
    if (snapshot == null && original == null) return const SizedBox.shrink();
    final senderName = _replySenderName(original, snapshot);
    final hasMedia =
        original != null && original.media.isNotEmpty && !original.isDeleted;
    return GestureDetector(
      onTap: original != null ? () => _scrollToMessage(m.replyToId!) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: hasMedia
            ? ReplyMediaPreview(
                replyToContent: original.content,
                replyToMediaUrl:
                    '$_baseUrl${original.media.first.url}?token=$_token',
                replyToMimeType: original.media.first.mimeType,
                replyToFileName: original.media.first.filename,
                replyToSenderName: senderName,
                isMe: mine,
              )
            : _replyPreviewTextOnly(m, mine, snapshot, original, senderName),
      ),
    );
  }

  Widget _replyPreviewTextOnly(Message m, bool mine, dynamic snapshot,
      Message? original, String senderName) {
    final onColor = _bubbleTextColor(mine);
    final barColor = mine ? Colors.white70 : _accentSoft;
    final previewText = _replyPreviewText(original, snapshot);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: mine ? Colors.white.withOpacity(0.15) : _quoteBgRecv(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: barColor, width: 3)),
      ),
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(senderName,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: barColor)),
        const SizedBox(height: 2),
        Text(previewText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: onColor.withOpacity(0.8))),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // FILE PICKER + UPLOAD
  // ══════════════════════════════════════════════
  Future<void> _pickAndSendFile() async {
    var result = await MediaPickerSheet.show(context);
    if (result == null || !mounted) return;

    // 🐛 LES SÉLECTEURS S'OUVRENT DEPUIS ICI, ET NON DEPUIS LA FEUILLE.
    //
    // La feuille se contente d'annoncer ce qu'il faut ouvrir : elle ne peut pas
    // se fermer PUIS rendre un résultat, le second `Navigator.pop` s'appliquant
    // alors à l'écran de discussion — c'est ce qui renvoyait à la liste des
    // conversations sans rien envoyer (constaté sur device le 17/08/2026). Cet
    // écran-ci, lui, reste vivant pendant toute la sélection.
    if (result is OuvrirSelecteurContact) {
      result = await ContactShareSheet.show(context);
    } else if (result is OuvrirEcranPosition) {
      result = await LocationShareScreen.open(context);
    } else if (result is OuvrirGalerie) {
      result = await MediaGalleryPickerScreen.open(context);
    } else if (result is OuvrirCamera) {
      result = await _prendrePhoto();
    }
    if (result == null || !mounted) return;

    // Contact sélectionné → vraie fiche de contact (message de type CONTACT).
    if (result is ContactShareResult) {
      await _sendContacts(result);
      return;
    }

    // Position sélectionnée → vraie position (message de type LOCATION).
    if (result is SharedLocation) {
      await _sendLocation(result);
      return;
    }

    // Médias sélectionnés
    final files = result as List<MediaPickResult>;
    if (files.isEmpty) return;

    // Aperçu : balayage entre les médias, retrait de l'un d'eux, légende.
    // ⚠️ On envoie la liste RENDUE par l'aperçu, pas celle de la sélection : un
    // média retiré doit disparaître de l'envoi.
    final apercu = await MediaCaptionScreen.open(context, files);
    if (apercu == null || apercu.fichiers.isEmpty) return; // annulé

    await _lanceEnvoiMedias(apercu.fichiers, apercu.legende);
  }

  // ══════════════════════════════════════════════
  // ENVOI DE MÉDIAS — progression, échec, réessai
  // ══════════════════════════════════════════════

  /// Prépare et lance l'envoi de [fichiers], en découpant par paquets de 10.
  ///
  /// ⚠️ **LE PLAFOND DE 10 VIENT DU SERVEUR** (`mediaIds: z.array().max(10)`).
  /// Avant, rien ne le connaissait côté client : sélectionner quinze photos les
  /// téléversait toutes — quinze requêtes réussies — puis se faisait refuser le
  /// message par un 422, et les quinze médias restaient orphelins en base. On
  /// découpe donc en plusieurs messages ; le regroupement à la lecture les
  /// réunira visuellement.
  Future<void> _lanceEnvoiMedias(
      List<MediaPickResult> fichiers, String? legende) async {
    final replyId = _replyTo?.id;
    if (_replyTo != null) setState(() => _replyTo = null);

    for (var debut = 0; debut < fichiers.length; debut += 10) {
      final lot = fichiers.sublist(
          debut, debut + 10 > fichiers.length ? fichiers.length : debut + 10);
      final premierMime = lot.first.mimeType;
      final msgType = premierMime.startsWith('image/')
          ? 'IMAGE'
          : premierMime.startsWith('video/')
              ? 'VIDEO'
              : premierMime.startsWith('audio/')
                  ? 'AUDIO'
                  : 'FILE';
      final tempId = "tmp-${DateTime.now().microsecondsSinceEpoch}-$debut";
      final envoi = EnvoiMedia(
        tempId: tempId,
        fichiers: lot,
        msgType: msgType,
        // La légende accompagne le PREMIER paquet seulement : répétée sur
        // chacun, elle apparaîtrait plusieurs fois dans le fil.
        legende: debut == 0 ? legende : null,
        replyToId: debut == 0 ? replyId : null,
      );

      // Bulle immédiate, avec la vignette locale : plus d'attente devant un
      // écran qui ne montre rien.
      final optimiste = Message(
        id: tempId,
        convId: widget.convId,
        senderId: _myId ?? "",
        content: envoi.legende,
        type: msgType,
        status: "SENT",
        replyToId: envoi.replyToId,
        replyTo: null,
        media: const [],
        createdAt: DateTime.now(),
      );
      setState(() {
        _envois[tempId] = envoi;
        _messages = [..._messages, optimiste];
        _rebuildCombined();
      });
      _scrollToBottom();

      // Séquentiel, et volontairement : téléverser dix fichiers en parallèle sur
      // une connexion mobile les ralentit tous et rend la progression illisible.
      await _executeEnvoi(envoi);
    }
  }

  /// Téléverse ce qui manque puis envoie le message. Reprend là où un échec
  /// précédent s'était arrêté.
  Future<void> _executeEnvoi(EnvoiMedia envoi) async {
    if (!mounted) return;
    setState(() {
      envoi.echoue = false;
      envoi.erreur = null;
    });

    final mediaRepo = context.read<MediaRepository>();
    try {
      for (var i = envoi.mediaIdsObtenus.length;
          i < envoi.fichiers.length;
          i++) {
        final f = envoi.fichiers[i];
        if (mounted) {
          setState(() {
            envoi.indexCourant = i;
            envoi.progressionFichier = 0;
          });
        }
        final envoye = await mediaRepo.upload(
          Uint8List.fromList(f.bytes),
          f.fileName,
          f.mimeType,
          durationMs: f.durationMs,
          onProgress: (envoyes, total) {
            if (!mounted || total <= 0) return;
            final ratio = envoyes / total;
            // Un setState par trame réseau ferait redessiner le fil des
            // centaines de fois : on ne remonte qu'au changement de centième.
            if ((ratio - envoi.progressionFichier).abs() < 0.01 && ratio < 1) {
              return;
            }
            setState(() => envoi.progressionFichier = ratio);
          },
        );
        envoi.mediaIdsObtenus.add(envoye.id);
      }

      final rt = context.read<RealtimeClient>();
      if (rt.connected) {
        rt.sendMultiMedia(
            widget.convId, envoi.mediaIdsObtenus, envoi.msgType, envoi.tempId,
            replyToId: envoi.replyToId, content: envoi.legende);
        // ⚠️ Trame sans accusé : si la socket tombe juste après, elle est perdue
        // en silence et la bulle resterait « Envoi… » à vie. On borne l'attente
        // de l'écho, qui remplace le message optimiste (`_onRealtimeEvent`).
        _armeAttenteEcho(envoi);
      } else {
        final msg = await context.read<ChatRepository>().sendMultiMedia(
            widget.convId, envoi.mediaIdsObtenus, envoi.msgType,
            replyToId: envoi.replyToId, content: envoi.legende);
        _cacheMsg(msg);
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == envoi.tempId);
            if (idx >= 0) {
              _messages[idx] = msg;
            } else {
              _messages = [..._messages, msg];
            }
            _envois.remove(envoi.tempId);
            _rebuildCombined();
          });
        }
      }
      _scrollToBottom();
    } on ApiException catch (e) {
      _marqueEchec(envoi, e.message);
    } catch (_) {
      _marqueEchec(envoi, tr(context, 'send_failed'));
    }
  }

  void _marqueEchec(EnvoiMedia envoi, String message) {
    if (!mounted) return;
    // Les médias déjà téléversés RESTENT dans `envoi.mediaIdsObtenus` : c'est ce
    // qui permet au réessai de ne pas les envoyer une seconde fois, et donc de
    // ne pas laisser d'orphelins en base.
    setState(() {
      envoi.echoue = true;
      envoi.erreur = message;
      envoi.progressionFichier = 0;
    });
  }

  /// Borne l'attente de l'écho du serveur pour un envoi parti par WebSocket.
  void _armeAttenteEcho(EnvoiMedia envoi) {
    _attentesEcho[envoi.tempId]?.cancel();
    _attentesEcho[envoi.tempId] = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (!_envois.containsKey(envoi.tempId)) return; // l'écho est arrivé
      // ⚠️ Le message a PEUT-ÊTRE été enregistré côté serveur : c'est l'écho
      // qui manque, pas nécessairement l'écriture. Un réessai peut donc créer un
      // doublon — d'où le choix laissé à l'utilisateur plutôt qu'un réessai
      // automatique, et le libellé qui parle de confirmation, pas d'échec.
      _marqueEchec(envoi, "Pas de confirmation du serveur");
    });
  }

  void _reessayerEnvoi(EnvoiMedia envoi) => _executeEnvoi(envoi);

  /// Abandonne un envoi échoué : la bulle disparaît du fil.
  ///
  /// Les médias déjà téléversés deviennent alors réellement orphelins — mais
  /// c'est un choix EXPLICITE de l'utilisateur, pas un accident silencieux comme
  /// avant. Une purge des médias sans message reste à écrire côté serveur.
  void _abandonneEnvoi(EnvoiMedia envoi) {
    _attentesEcho.remove(envoi.tempId)?.cancel();
    setState(() {
      _envois.remove(envoi.tempId);
      _messages = _messages.where((m) => m.id != envoi.tempId).toList();
      _rebuildCombined();
    });
  }

  Future<void> _uploadAndSend(
      List<int> bytes, String filename, String mime, String msgType,
      {int? durationMs}) async {
    setState(() => _uploading = true);
    final replyId = _replyTo?.id;
    final replyMsg = _replyTo;
    final replySnapshot = replyMsg != null
        ? ReplyPreview(
            id: replyMsg.id,
            senderId: replyMsg.senderId,
            type: replyMsg.type,
            content: replyMsg.isDeleted ? null : replyMsg.content,
            isDeleted: replyMsg.isDeleted)
        : null;
    if (mounted) setState(() => _replyTo = null);
    final media = context.read<MediaRepository>();
    final rt = context.read<RealtimeClient>();
    try {
      final uploaded = await media.upload(
          Uint8List.fromList(bytes), filename, mime,
          durationMs: durationMs);
      if (rt.connected) {
        rt.sendMedia(widget.convId, uploaded.id, msgType,
            "tmp-${DateTime.now().microsecondsSinceEpoch}",
            replyToId: replyId);
      } else {
        final msg = await context
            .read<ChatRepository>()
            .sendMedia(widget.convId, uploaded.id, msgType, replyToId: replyId);
        if (mounted) setState(() => _messages = [..._messages, msg]);
      }
      _scrollToBottom();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(tr(context, 'send_failed'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Prise de vue, depuis l'écran de discussion et non depuis la feuille : la
  /// caméra est une application externe, et la feuille aurait été détruite
  /// pendant son affichage.
  Future<List<MediaPickResult>?> _prendrePhoto() async {
    try {
      final photo = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) return null;
      final octets = await photo.readAsBytes();
      return [
        MediaPickResult(
          bytes: octets,
          fileName: photo.name,
          mimeType: 'image/jpeg',
          path: photo.path,
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════
  // CONTACT PARTAGÉ
  // ══════════════════════════════════════════════

  /// Envoie une ou plusieurs fiches de contact Alanya (message `CONTACT`).
  ///
  /// La charge utile est du JSON dans `content` — format tenu par le serveur,
  /// voir `models/message_payload.dart`. Aucun média : la photo est celle du
  /// COMPTE Alanya, déjà servie par le serveur, et la charge n'en transporte
  /// que l'adresse.
  Future<void> _sendContacts(ContactShareResult resultat) async {
    if (resultat.contacts.isEmpty) return;
    final replyId = _replyTo?.id;
    final replyMsg = _replyTo;
    final replySnapshot = replyMsg != null
        ? ReplyPreview(
            id: replyMsg.id,
            senderId: replyMsg.senderId,
            type: replyMsg.type,
            content: replyMsg.isDeleted ? null : replyMsg.content,
            isDeleted: replyMsg.isDeleted)
        : null;
    setState(() {
      _uploading = true;
      _replyTo = null;
    });

    final charge = encodeContacts(resultat.contacts);
    final rt = context.read<RealtimeClient>();
    try {
      if (rt.connected) {
        final tempId = "tmp-${DateTime.now().microsecondsSinceEpoch}";
        // Bulle immédiate, remplacée par l'écho du serveur (qui renvoie le
        // `tempId`) : même mécanique que pour un message texte.
        final optimistic = Message(
          id: tempId,
          convId: widget.convId,
          senderId: _myId ?? "",
          content: charge,
          type: "CONTACT",
          status: "SENT",
          replyToId: replyId,
          replyTo: replySnapshot,
          media: const [],
          createdAt: DateTime.now(),
        );
        setState(() {
          _messages = [..._messages, optimistic];
          _rebuildCombined();
        });
        rt.sendStructured(widget.convId, "CONTACT", charge, tempId,
            replyToId: replyId);
      } else {
        final msg = await context.read<ChatRepository>().sendStructured(
            widget.convId, "CONTACT", charge,
            replyToId: replyId);
        _cacheMsg(msg);
        if (mounted) {
          setState(() {
            _messages = [..._messages, msg];
            _rebuildCombined();
          });
        }
      }
      _scrollToBottom();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(tr(context, 'send_failed'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Contacts portés par un message, ou liste vide si la charge est illisible.
  List<SharedContact> _contactsDe(Message m) =>
      contactsDepuisContenu(m.content) ?? const [];

  // ══════════════════════════════════════════════
  // POSITION PARTAGÉE
  // ══════════════════════════════════════════════

  /// Envoie une position (message de type `LOCATION`).
  ///
  /// Aucun média : la charge JSON de `content` suffit, et la carte est dessinée
  /// chez le destinataire à partir des coordonnées. Envoyer une image de carte
  /// serait plus lourd, moins net, et non zoomable.
  Future<void> _sendLocation(SharedLocation position) async {
    final replyId = _replyTo?.id;
    final replyMsg = _replyTo;
    final replySnapshot = replyMsg != null
        ? ReplyPreview(
            id: replyMsg.id,
            senderId: replyMsg.senderId,
            type: replyMsg.type,
            content: replyMsg.isDeleted ? null : replyMsg.content,
            isDeleted: replyMsg.isDeleted)
        : null;
    setState(() {
      _uploading = true;
      _replyTo = null;
    });

    final charge = encodeLocation(position);
    final rt = context.read<RealtimeClient>();
    try {
      if (rt.connected) {
        final tempId = "tmp-${DateTime.now().microsecondsSinceEpoch}";
        final optimistic = Message(
          id: tempId,
          convId: widget.convId,
          senderId: _myId ?? "",
          content: charge,
          type: "LOCATION",
          status: "SENT",
          replyToId: replyId,
          replyTo: replySnapshot,
          media: const [],
          createdAt: DateTime.now(),
        );
        setState(() {
          _messages = [..._messages, optimistic];
          _rebuildCombined();
        });
        rt.sendStructured(widget.convId, "LOCATION", charge, tempId,
            replyToId: replyId);
      } else {
        final msg = await context.read<ChatRepository>().sendStructured(
            widget.convId, "LOCATION", charge,
            replyToId: replyId);
        _cacheMsg(msg);
        if (mounted) {
          setState(() {
            _messages = [..._messages, msg];
            _rebuildCombined();
          });
        }
      }
      _scrollToBottom();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(tr(context, 'send_failed'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Ouvre la discussion avec un contact reçu (compte Alanya seulement).
  ///
  /// La conversation est créée à la volée si elle n'existe pas — `createDirect`
  /// récupère l'existante ou la crée, exactement comme depuis la fiche contact.
  Future<void> _ouvrirDiscussionContact(SharedContact contact) async {
    final id = contact.alanyaId;
    if (id == null) return;
    try {
      final convId = await context.read<ChatRepository>().createDirect(id);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          convId: convId,
          title: contact.displayName,
          avatarUrl: contact.avatarUrl,
          otherPublicNumber: id,
        ),
      ));
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError("Impossible d'ouvrir la discussion");
    }
  }

  /// Appelle un contact reçu (compte Alanya seulement).
  Future<void> _appelerContact(SharedContact contact) async {
    final id = contact.alanyaId;
    if (id == null) return;
    final cc = context.read<CallController>();
    try {
      final convId = await context.read<ChatRepository>().createDirect(id);
      if (!mounted) return;
      await cc.startOutgoing(convId, "AUDIO", contact.displayName);
      if (!mounted) return;
      // Sans cette ouverture, l'appel démarre sans que rien ne s'affiche —
      // seul le bandeau global le signale (même enchaînement que la fiche
      // contact et le clavier d'appel).
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ActiveCallScreen(),
      ));
    } catch (e) {
      // `messageErreurAppel` traite déjà l'ApiException : le message du serveur
      // passe tel quel (« Le correspondant est déjà en appel »), et c'est le
      // point unique des trois écrans qui lancent un appel.
      _showError(messageErreurAppel(e));
    }
  }

  /// Ajoute un contact reçu au répertoire **Alanya**.
  ///
  /// C'est bien celui-ci et non le carnet d'adresses du téléphone : c'est le
  /// répertoire dont l'application se sert pour retrouver quelqu'un, l'appeler
  /// et lui écrire — et il n'exige aucune permission système.
  ///
  /// Le doublon n'est pas une erreur : `ALREADY_CONTACT` est annoncé comme un
  /// fait (« déjà dans tes contacts »), pas comme un échec.
  Future<void> _ajouterContactAlanya(SharedContact contact) async {
    final id = contact.alanyaId;
    if (id == null) return;
    try {
      await context.read<ContactsRepository>().add(id, alias: contact.name);
      if (!mounted) return;
      showAppSnackBar("${contact.displayName} ajouté à tes contacts");
    } on ApiException catch (e) {
      if (e.code == "ALREADY_CONTACT") {
        showAppSnackBar("${contact.displayName} est déjà dans tes contacts");
        return;
      }
      _showError(e.message);
    } catch (_) {
      _showError("Impossible d'ajouter ce contact");
    }
  }

  // ══════════════════════════════════════════════
  // VOICE RECORDING
  // ══════════════════════════════════════════════
  void _startRecordTimer() {
    _recordTimer?.cancel();
    _recordDuration = Duration.zero;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _recordDuration =
            DateTime.now().difference(_recordStarted ?? DateTime.now());
      });
    });
  }

  void _stopRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _startVoiceRecord() async {
    if (_uploading || _recording || _voiceActive) return;
    _voiceActive = true;
    if (!_voiceRecorder.isSupported) {
      _voiceActive = false;
      _showError(tr(context, 'micro_unavailable_platform'));
      return;
    }
    final ok = await _voiceRecorder.start();
    if (!ok || !_voiceActive) {
      if (ok) _voiceRecorder.cancel();
      _voiceActive = false;
      if (ok) _showError(tr(context, 'micro_unavailable'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordLocked = false;
      _recordStarted = DateTime.now();
    });
    _startRecordTimer();
    _typingDebounce?.cancel();
    _emitTyping(false); // pas de "écrit" pendant un vocal
    _emitRecording(true);
  }

  Future<void> _stopVoiceRecord({bool cancel = false}) async {
    _voiceActive = false;
    if (!_recording) return;
    _stopRecordTimer();
    // `_micHeld` remis à faux par précaution : la gestuelle a pu être
    // interrompue sans que onLongPressEnd ne se déclenche (verrouillage,
    // rebuild du composeur). Le laisser à vrai maintiendrait le micro agrandi.
    setState(() {
      _recording = false;
      _recordLocked = false;
      _micHeld = false;
      _recordDuration = Duration.zero;
    });
    _emitRecording(false);
    if (cancel) {
      _voiceRecorder.cancel();
      return;
    }
    final result = await _voiceRecorder.stop();
    if (result == null || result.bytes.isEmpty) return;
    final ext = kIsWeb ? "webm" : "m4a";
    final mime = kIsWeb ? "audio/webm" : "audio/mp4";
    await _uploadAndSend(result.bytes,
        "vocal-${DateTime.now().millisecondsSinceEpoch}.$ext", mime, "AUDIO",
        durationMs: result.durationMs);
  }

  String _ext(String name) {
    final i = name.lastIndexOf(".");
    return i >= 0 ? name.substring(i + 1).toLowerCase() : "";
  }

  String _mimeFromName(String name) {
    switch (_ext(name)) {
      case "png":
        return "image/png";
      case "gif":
        return "image/gif";
      case "webp":
        return "image/webp";
      case "jpg":
      case "jpeg":
        return "image/jpeg";
      case "pdf":
        return "application/pdf";
      case "doc":
        return "application/msword";
      case "docx":
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
      case "xls":
        return "application/vnd.ms-excel";
      case "xlsx":
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
      case "ppt":
      case "pptx":
        return "application/vnd.ms-powerpoint";
      case "txt":
        return "text/plain";
      case "csv":
        return "text/csv";
      case "zip":
        return "application/zip";
      case "rar":
        return "application/vnd.rar";
      case "7z":
        return "application/x-7z-compressed";
      case "mp3":
        return "audio/mpeg";
      case "wav":
        return "audio/wav";
      case "mp4":
        return "video/mp4";
      case "mov":
        return "video/quicktime";
      default:
        return "application/octet-stream";
    }
  }

  Future<String> _freshToken() async {
    _token = await context.read<TokenStorage>().accessToken;
    return _token ?? '';
  }

  String _mediaUrl(MessageMedia m) => "$_baseUrl${m.url}?token=${_token ?? ''}";
  String _downloadUrl(MessageMedia m) =>
      "$_baseUrl${m.url}?download=1&token=${_token ?? ''}";

  Future<void> _download(MessageMedia m) async {
    final token = await _freshToken();
    final url = "$_baseUrl${m.url}?download=1&token=$token";
    final name = m.filename ?? "fichier-${m.id}";
    final path = await downloadUrl(url, name);
    if (!mounted) return;
    if (path != null) {
      showAppSnackBar("Enregistré dans Alanya/ : $name");
    } else {
      showAppSnackBar("Échec du téléchargement");
    }
  }

  /// Ouvre un document / type sans lecteur intégré : télécharge dans le cache
  /// app (chemin réel, une seule fois) puis passe la main à l'OS (OpenFilex).
  Future<void> _openDocument(MessageMedia m) async {
    final token = await _freshToken();
    final url = "$_baseUrl${m.url}?download=1&token=$token";
    final name = m.filename ?? "fichier-${m.id}";
    showAppSnackBar("Ouverture…");
    final path = await downloadToCache(url, name);
    if (!mounted) return;
    if (path != null) {
      await openLocalFile(path);
    } else {
      showAppSnackBar("Impossible d'ouvrir le fichier");
    }
  }

  // Collecte tous les médias image/vidéo de la conversation (ordre du fil) pour
  // la galerie navigable (swipe entre médias).
  Future<List<ConvMediaItem>> _galleryItems() async {
    final token = await _freshToken();
    final items = <ConvMediaItem>[];
    for (final msg in _messages) {
      for (final media in msg.media) {
        final t = MediaHelper.detectType(media.mimeType, media.filename);
        if (t == AlanyaMediaType.image || t == AlanyaMediaType.video) {
          items.add(ConvMediaItem(
            id: media.id,
            url: "$_baseUrl${media.url}?token=$token",
            downloadUrl: "$_baseUrl${media.url}?download=1&token=$token",
            filename: media.filename ?? "",
            isVideo: t == AlanyaMediaType.video,
          ));
        }
      }
    }
    return items;
  }

  // Ouvre la visionneuse navigable positionnée sur le média [mediaId].
  Future<void> _openGallery(String mediaId) async {
    final items = await _galleryItems();
    if (!mounted || items.isEmpty) return;
    var idx = items.indexWhere((it) => it.id == mediaId);
    if (idx < 0) idx = 0;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaGalleryViewer(items: items, initialIndex: idx),
    ));
  }

  Future<void> _openImageViewer(Message m) async =>
      _openGallery(m.media.first.id);

  Future<void> _openVideoViewer(Message m) async =>
      _openGallery(m.media.first.id);

  Future<void> _openPdfViewer(Message m) async {
    final token = await _freshToken();
    final media = m.media.first;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
            pdfUrl: "$_baseUrl${media.url}?token=$token",
            downloadUrl: "$_baseUrl${media.url}?download=1&token=$token",
            filename: media.filename ?? "document-${media.id}.pdf")));
  }

  /// Amène le fil sur le dernier message.
  ///
  /// [immediat] sert à l'OUVERTURE de la conversation : on se pose en bas sans
  /// animation, et on recommence tant que le fond bouge encore.
  ///
  /// ⚠️ Une seule tentative ne suffit pas — c'est ce qui faisait ouvrir la
  /// conversation AU MILIEU du fil. `ListView.builder` construit ses éléments
  /// paresseusement : au premier frame, `maxScrollExtent` ne décrit que les
  /// quelques messages déjà bâtis, et on visait donc un fond provisoire. Le
  /// chargement des médias déplace ensuite le vrai fond une seconde fois.
  ///
  /// Sans animation à l'ouverture, volontairement : dérouler tout l'historique
  /// sous les yeux de l'utilisateur à chaque entrée n'apporte rien et donne
  /// l'impression que l'écran part tout seul.

  /// Amène le fil sur le dernier message.
  ///
  /// ✅ **Devenu trivial depuis que la liste est inversée** : le fond est le
  /// décalage **0**, une valeur connue d'avance et qui ne bouge jamais.
  ///
  /// Ce que cela remplace mérite d'être noté, car c'était la source d'une
  /// partie des sauts : l'ancienne version visait `maxScrollExtent`, qui
  /// GRANDIT à mesure que `ListView.builder` construit paresseusement ses
  /// éléments. Elle devait donc reposer le défilement image après image, en
  /// s'arrêtant « quand le fond cesse de bouger » — jusqu'à dix fois. Les
  /// traces du device montrent cette course en direct : `max` passe de 7592 à
  /// 7733 puis retombe à 7343 en moins d'une seconde, pendant que le
  /// défilement essaie de le rattraper. Plus rien de tout cela n'est
  /// nécessaire.
  void _scrollToBottom({bool immediat = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (immediat) {
        _scrollCtrl.jumpTo(0);
      } else {
        _scrollCtrl.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _showError(String m) => showAppSnackBar(m);

  // ══════════════════════════════════════════════
  // DELETE / FORWARD / OPTIONS
  // ══════════════════════════════════════════════
  Future<void> _deleteMessage(Message m) async {
    final canDeleteForAll = m.senderId == _myId && !m.isDeleted;
    final scope = await _showDeleteDialog(canDeleteForAll);
    if (scope == null || !mounted) return;
    final rt = context.read<RealtimeClient>();
    try {
      if (rt.connected) {
        rt.deleteMessage(m.id, scope: scope);
      } else {
        await context
            .read<ChatRepository>()
            .deleteMessage(widget.convId, m.id, scope: scope);
      }
      if (!mounted) return;
      setState(() {
        if (scope == "me") {
          _messages = _messages.where((msg) => msg.id != m.id).toList();
        } else {
          _messages = _messages
              .map((msg) => msg.id == m.id
                  ? Message(
                      id: m.id,
                      convId: m.convId,
                      senderId: m.senderId,
                      content: null,
                      type: m.type,
                      status: m.status,
                      replyToId: m.replyToId,
                      replyTo: m.replyTo,
                      deletedAt: DateTime.now(),
                      media: const [],
                      createdAt: m.createdAt)
                  : msg)
              .toList();
        }
      });
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(tr(context, 'send_failed'));
    }
  }

  Future<String?> _showDeleteDialog(bool canDeleteForAll) {
    return showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: Icon(Icons.delete_outline, color: _iconNeutral),
                  title: Text(tr(context, 'delete_for_me')),
                  onTap: () => Navigator.pop(ctx, "me")),
              if (canDeleteForAll)
                ListTile(
                    leading: Icon(Icons.delete_forever, color: _danger),
                    title: Text(tr(context, 'delete_for_everyone')),
                    onTap: () => Navigator.pop(ctx, "everyone")),
            ])));
  }

  Future<void> _forwardMessage(Message m) async {
    final conversations =
        await context.read<ChatRepository>().listConversations();
    if (!mounted) return;
    final picked = <String>{};
    await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _ForwardPicker(
            conversations:
                conversations.where((c) => c.id != widget.convId).toList(),
            title: tr(context, 'forward_to'))).then((result) {
      if (result != null) picked.addAll(result);
    });
    if (picked.isEmpty || !mounted) return;
    final rt = context.read<RealtimeClient>();
    try {
      if (rt.connected) {
        rt.forwardMessage(m.id, picked.toList());
      } else {
        await context
            .read<ChatRepository>()
            .forwardMessage(widget.convId, m.id, picked.toList());
      }
      if (mounted) showAppSnackBar(tr(context, 'forwarded_success'));
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(tr(context, 'send_failed'));
    }
  }

  static const List<String> _reactionEmojis = [
    "👍",
    "❤️",
    "😂",
    "😮",
    "😢",
    "🙏"
  ];

  /// Envoie une réaction et l'applique en optimiste (le serveur rediffuse aussi).
  void _react(Message m, String emoji) {
    final myId = _myId;
    if (myId == null || myId.isEmpty) return;
    context.read<RealtimeClient>().sendReaction(widget.convId, m.id, emoji);
    setState(() {
      final mine = m.reactions.where((r) => r.userId == myId).toList();
      final had = mine.isNotEmpty && mine.first.emoji == emoji;
      final updated = m.reactions.where((r) => r.userId != myId).toList();
      if (!had) updated.add(MessageReaction(userId: myId, emoji: emoji));
      m.reactions = updated;
    });
  }

  String? _myReactionOn(Message m) {
    for (final r in m.reactions) {
      if (r.userId == _myId) return r.emoji;
    }
    return null;
  }

  // Appui long façon WhatsApp : sélectionne le message (header contextuel) et
  // affiche une bulle de réactions flottante et animée au-dessus du message.
  void _openMessageActions(Message m) {
    if (m.isDeleted) {
      _showMessageOptions(m); // message supprimé → menu minimal (repli)
      return;
    }
    final ctx = _messageKeys[m.id]?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      _showMessageOptions(m); // repli si on ne peut pas positionner la bulle
      return;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    _clearSelection();
    setState(() => _selectedMessageId = m.id);
    final overlay = OverlayEntry(
      builder: (_) => _ReactionBarrier(
        anchor: rect,
        mine: m.senderId == _myId,
        emojis: _reactionEmojis,
        myEmoji: _myReactionOn(m),
        onSelect: (e) {
          _clearSelection();
          _react(m, e);
        },
        onDismiss: _clearSelection,
      ),
    );
    _actionsOverlay = overlay;
    Overlay.of(context).insert(overlay);
  }

  void _clearSelection() {
    _actionsOverlay?.remove();
    _actionsOverlay = null;
    if (mounted && _selectedMessageId != null) {
      setState(() => _selectedMessageId = null);
    }
  }

  // Infos du message : qui a lu (accusés dérivés de lastReadAt), + en attente.
  void _showMessageInfo(Message m) {
    final repo = context.read<ChatRepository>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => FutureBuilder<Map<String, dynamic>>(
        future: repo.getMessageInfo(widget.convId, m.id),
        builder: (fctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 160, child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError || snap.data == null) {
            return const SizedBox(
                height: 120, child: Center(child: Text("Infos indisponibles")));
          }
          final members = ((snap.data!["members"] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final readList = members.where((x) => x["read"] == true).toList();
          final pending = members.where((x) => x["read"] != true).toList();
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text("Infos du message",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const Divider(height: 1),
              _infoSection(
                  Icons.done_all, AlanyaColors.tickRead, "Lu", readList),
              _infoSection(Icons.done, _mutedIcon, "En attente", pending),
              if (readList.isEmpty && pending.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("Aucun destinataire.")),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  Widget _infoSection(IconData icon, Color color, String title,
      List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text("$title (${list.length})",
              style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
      ...list.map((x) {
        final readAtStr = x["readAt"] as String?;
        final when = readAtStr != null ? _readAtLabel(readAtStr) : null;
        return ListTile(
          dense: true,
          leading: Icon(Icons.person_outline, color: _mutedIcon),
          title: Text((x["name"] as String?) ?? ""),
          trailing: when != null
              ? Text(when, style: TextStyle(fontSize: 12, color: _muted))
              : null,
        );
      }),
    ]);
  }

  String _readAtLabel(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return "";
    return _time(dt.toLocal());
  }

  Future<void> _loadDisappearing() async {
    try {
      final s =
          await context.read<ChatRepository>().getDisappearing(widget.convId);
      if (mounted) setState(() => _disappearingSeconds = s);
    } catch (_) {}
  }

  static const Map<int, String> _disappearingOptions = {
    0: "Désactivé",
    86400: "24 heures",
    604800: "7 jours",
    7776000: "90 jours",
  };

  String _disappearingLabel(int s) => _disappearingOptions[s] ?? "Personnalisé";

  void _setDisappearing(int seconds) {
    setState(() => _disappearingSeconds = seconds);
    final rt = context.read<RealtimeClient>();
    if (rt.connected) {
      rt.setDisappearing(widget.convId, seconds);
    } else {
      context
          .read<ChatRepository>()
          .setDisappearing(widget.convId, seconds)
          .catchError((_) {});
    }
  }

  void _showDisappearingDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.timer_outlined, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text("Messages éphémères",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              "Les nouveaux messages disparaîtront après la durée choisie, pour tout le monde.",
              style: TextStyle(fontSize: 13, color: _muted),
            ),
          ),
          const Divider(height: 1),
          ..._disappearingOptions.entries.map((e) {
            final selected = e.key == _disappearingSeconds;
            return ListTile(
              title: Text(e.value),
              trailing: selected ? Icon(Icons.check, color: _accent) : null,
              onTap: () {
                Navigator.pop(ctx);
                _setDisappearing(e.key);
              },
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _loadPinned() async {
    try {
      final data =
          await context.read<ChatRepository>().getPinned(widget.convId);
      if (!mounted) return;
      setState(() => _pinnedMessageId = data["pinnedMessageId"] as String?);
    } catch (_) {}
  }

  // Épingle / détache un message pour toute la conversation.
  void _togglePin(Message m) {
    final newPinned = _pinnedMessageId == m.id ? null : m.id;
    setState(() => _pinnedMessageId = newPinned);
    final rt = context.read<RealtimeClient>();
    if (rt.connected) {
      rt.pinMessage(widget.convId, newPinned);
    } else {
      context
          .read<ChatRepository>()
          .pinMessage(widget.convId, newPinned)
          .catchError((_) {});
    }
  }

  String _pinnedPreviewText(Message m) {
    if (m.isDeleted) return "Message supprimé";
    // Même raison que pour la citation d'une réponse : le bandeau ne montre
    // qu'une ligne, et la charge d'un message structuré est du JSON.
    final structure = apercuStructure(m.type, m.content);
    if (structure != null) return structure;
    switch (m.type) {
      case "IMAGE":
        return "Photo";
      case "VIDEO":
        return "Vidéo";
      case "AUDIO":
        return "Message vocal";
      case "FILE":
        return "Fichier";
      default:
        return m.content ?? "";
    }
  }

  Widget _pinnedBanner() {
    final id = _pinnedMessageId;
    if (id == null) return const SizedBox.shrink();
    Message? pm;
    for (final m in _messages) {
      if (m.id == id) {
        pm = m;
        break;
      }
    }
    final preview = pm == null ? "Appuyez pour voir" : _pinnedPreviewText(pm);
    return Material(
      color: _composerBg,
      child: InkWell(
        onTap: () => _scrollToMessage(id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _hairline)),
          ),
          child: Row(children: [
            Icon(Icons.push_pin, size: 18, color: _accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Message épinglé",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _accent)),
                  Text(preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: _muted)),
                ],
              ),
            ),
            IconButton(
              tooltip: "Détacher",
              icon: Icon(Icons.close, size: 20, color: _muted45),
              onPressed: () {
                setState(() => _pinnedMessageId = null);
                final rt = context.read<RealtimeClient>();
                if (rt.connected) {
                  rt.pinMessage(widget.convId, null);
                } else {
                  context
                      .read<ChatRepository>()
                      .pinMessage(widget.convId, null)
                      .catchError((_) {});
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  // Bascule le favori (étoile) — optimiste, rollback si l'API échoue.
  void _toggleStar(Message m) {
    final newVal = !m.starred;
    setState(() => m.starred = newVal);
    context
        .read<ChatRepository>()
        .toggleStar(widget.convId, m.id, newVal)
        .catchError((_) {
      if (mounted) setState(() => m.starred = !newVal);
    });
  }

  Widget _reactionPickerRow(Message m, BuildContext ctx) {
    final mine = m.reactions.where((r) => r.userId == _myId).toList();
    final myEmoji = mine.isNotEmpty ? mine.first.emoji : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _reactionEmojis.map((e) {
          final selected = e == myEmoji;
          return InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              Navigator.pop(ctx);
              _react(m, e);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? themed(context,
                            light: AlanyaColors.terracotta,
                            dark: AlanyaColors.terracottaNuit)
                        .withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
              child: Text(e, style: const TextStyle(fontSize: 26)),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showMessageOptions(Message m) {
    showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!m.isDeleted) _reactionPickerRow(m, ctx),
              if (!m.isDeleted) const Divider(height: 1),
              if (!m.isDeleted) ...[
                ListTile(
                    leading: Icon(Icons.reply, color: _accent),
                    title: Text(tr(context, 'reply')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _setReplyTo(m);
                    }),
                if (m.senderId == _myId && m.type == 'TEXT')
                  ListTile(
                      leading: Icon(Icons.edit_outlined, color: _positive),
                      title: const Text("Modifier"),
                      onTap: () {
                        Navigator.pop(ctx);
                        _startEdit(m);
                      }),
                ListTile(
                    leading: Icon(Icons.forward, color: _positive),
                    title: Text(tr(context, 'forward')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _forwardMessage(m);
                    }),
                ListTile(
                    leading: Icon(Icons.copy, color: _iconNeutral),
                    title: Text(tr(context, 'copy')),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (m.content != null) {
                        Clipboard.setData(ClipboardData(text: m.content!));
                        showAppSnackBar(tr(context, 'copied'));
                      }
                    }),
              ],
              if (!m.isDeleted && m.media.isNotEmpty)
                ListTile(
                    leading: Icon(Icons.download_outlined, color: _iconNeutral),
                    title: const Text("Enregistrer"),
                    onTap: () {
                      Navigator.pop(ctx);
                      _download(m.media.first);
                    }),
              ListTile(
                  leading: Icon(
                      m.isDeleted ? Icons.delete_outline : Icons.delete,
                      color: _danger),
                  title: Text(tr(context, 'delete')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteMessage(m);
                  }),
            ])));
  }

  Future<void> _startCall(String type) async {
    final cc = context.read<CallController>();
    try {
      await cc.startOutgoing(widget.convId, type, widget.title);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true, builder: (_) => const ActiveCallScreen()));
    } catch (e) {
      // Le message vient de `messageErreurAppel`, partagé avec le clavier et la
      // fiche de contact. Ici manquait la clause `on ApiException` : appeler
      // quelqu'un déjà en ligne affichait « vérifie ta connexion » au lieu du
      // « Le correspondant est déjà en appel » que le serveur renvoyait.
      _showError(messageErreurAppel(e));
    }
  }

  // ══════════════════════════════════════════════
  // APPBAR
  // ══════════════════════════════════════════════
  PreferredSizeWidget _whatsappAppBar() {
    return AppBar(
      backgroundColor: _appBarBg,
      foregroundColor: _onAppBar,
      leadingWidth: 40,
      titleSpacing: 0,
      title: InkWell(
        onTap: widget.isGroup ? _openGroupInfo : _openContactInfo,
        child: Row(children: [
          GestureDetector(
              onTap: _openAvatarViewer,
              child: AvatarCircle(
                  name: widget.title,
                  avatarUrl: widget.avatarUrl,
                  radius: 18,
                  backgroundColor: Colors.white24)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (widget.isGroup)
                  Text("${widget.memberNames.length} membres",
                      style: TextStyle(fontSize: 11, color: _onAppBarSub))
                else
                  // Présence LIVE : lit le PresenceStore (mis à jour par les events WS
                  // `presence`), avec repli sur les données REST passées au widget.
                  Consumer<PresenceStore>(builder: (ctx, presence, _) {
                    final uid = widget.otherUserId;
                    final online =
                        (uid != null ? presence.isOnline(uid) : null) ??
                            (widget.otherIsOnline == 1);
                    final ls = (uid != null ? presence.lastSeen(uid) : null) ??
                        widget.otherLastSeen;
                    String? sub;
                    if (online) {
                      sub = "en ligne";
                    } else if (ls != null) {
                      sub = _lastSeenLabel(ls);
                    } else if (widget.otherStatusMsg?.isNotEmpty == true) {
                      sub = widget.otherStatusMsg;
                    }
                    if (sub == null) return const SizedBox.shrink();
                    // Modèle Nuit : la présence est le seul accent chaud de l'en-tête.
                    return Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: _dark
                                ? AlanyaColors.terracottaNuitLight
                                : Colors.white70));
                  }),
              ])),
        ]),
      ),
      actions: [
        IconButton(
            tooltip: "Rechercher",
            icon: const Icon(Icons.search),
            onPressed: _openSearch),
        if (!widget.isGroup) ...[
          IconButton(
              tooltip: "Appel vidéo",
              icon: const Icon(Icons.videocam),
              onPressed: () => _startCall("VIDEO")),
          IconButton(
              tooltip: "Appel audio",
              icon: const Icon(Icons.call),
              onPressed: () => _startCall("AUDIO")),
        ],
        PopupMenuButton<String>(
          tooltip: "Plus",
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'disappearing') _showDisappearingDialog();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'disappearing',
              child: Row(children: [
                Icon(
                    _disappearingSeconds > 0
                        ? Icons.timer
                        : Icons.timer_outlined,
                    size: 20,
                    color: _accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_disappearingSeconds > 0
                      ? "Éphémères · ${_disappearingLabel(_disappearingSeconds)}"
                      : "Messages éphémères"),
                ),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  // AppBar de recherche dans la conversation (loupe → ce mode).
  PreferredSizeWidget _searchAppBar() {
    final total = _searchResultIds.length;
    final pos = total == 0 ? 0 : _searchIndex + 1;
    final hasQuery = _searchCtrl.text.trim().isNotEmpty;
    return AppBar(
      backgroundColor: _appBarBg,
      foregroundColor: _onAppBar,
      titleSpacing: 0,
      leading: IconButton(
          icon: const Icon(Icons.arrow_back), onPressed: _closeSearch),
      title: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: TextStyle(color: _onAppBar, fontSize: 16),
        cursorColor: _onAppBar,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: "Rechercher…",
          hintStyle: TextStyle(color: _onAppBarSub),
          border: InputBorder.none,
        ),
      ),
      actions: [
        if (_searchLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_onAppBar)),
              ),
            ),
          )
        else if (hasQuery) ...[
          Center(
            child: Text(total == 0 ? "0" : "$pos/$total",
                style: TextStyle(color: _onAppBar, fontSize: 13)),
          ),
          IconButton(
              tooltip: "Plus ancien",
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: total == 0 ? null : () => _searchNav(1)),
          IconButton(
              tooltip: "Plus récent",
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: total == 0 ? null : () => _searchNav(-1)),
        ],
      ],
    );
  }

  // Header CONTEXTUEL affiché quand un message est sélectionné (appui long).
  // Icônes Material propres (jamais d'emoji) : Répondre, Transférer, Supprimer,
  // + menu 3 points (Copier, Modifier). (Étoile/Épingler/Infos = lot suivant.)
  PreferredSizeWidget _selectionAppBar(Message m) {
    final mine = m.senderId == _myId;
    final hasText = (m.content ?? '').isNotEmpty;
    return AppBar(
      backgroundColor: _appBarBg,
      foregroundColor: _onAppBar,
      leading: IconButton(
          tooltip: "Annuler",
          icon: const Icon(Icons.close),
          onPressed: _clearSelection),
      title: const SizedBox.shrink(),
      actions: [
        IconButton(
            tooltip: "Répondre",
            icon: const Icon(Icons.reply),
            onPressed: () {
              _clearSelection();
              _setReplyTo(m);
            }),
        IconButton(
            tooltip: m.starred ? "Retirer des favoris" : "Ajouter aux favoris",
            icon: Icon(m.starred ? Icons.star : Icons.star_border),
            onPressed: () {
              _clearSelection();
              _toggleStar(m);
            }),
        IconButton(
            tooltip: "Transférer",
            icon: const Icon(Icons.forward),
            onPressed: () {
              _clearSelection();
              _forwardMessage(m);
            }),
        IconButton(
            tooltip: "Supprimer",
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              _clearSelection();
              _deleteMessage(m);
            }),
        PopupMenuButton<String>(
          tooltip: "Plus",
          icon: const Icon(Icons.more_vert),
          // Retire la bulle de réactions (et sa barrière) dès l'ouverture du menu,
          // sinon la barrière intercepte le tap sur les items → « rien ne se passe ».
          onOpened: () {
            _actionsOverlay?.remove();
            _actionsOverlay = null;
          },
          onSelected: (v) {
            _clearSelection();
            if (v == 'copy' && m.content != null) {
              Clipboard.setData(ClipboardData(text: m.content!));
              showAppSnackBar(tr(context, 'copied'));
            } else if (v == 'edit') {
              _startEdit(m);
            } else if (v == 'pin') {
              _togglePin(m);
            } else if (v == 'info') {
              _showMessageInfo(m);
            } else if (v == 'download' && m.media.isNotEmpty) {
              _download(m.media.first);
            }
          },
          itemBuilder: (_) => [
            if (mine && !m.isDeleted)
              PopupMenuItem(
                  value: 'info',
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 20, color: _iconNeutral),
                    const SizedBox(width: 12),
                    const Text("Infos"),
                  ])),
            // Enregistrer dans le stockage public du téléphone.
            //
            // ⚠️ `_download` existait déjà, ÉCRIT ET FONCTIONNEL, mais n'était
            // appelé de nulle part : le destinataire pouvait ouvrir un fichier,
            // jamais le garder. C'est le « téléchargement côté destinataire »
            // demandé pour les fichiers.
            if (!m.isDeleted && m.media.isNotEmpty)
              PopupMenuItem(
                  value: 'download',
                  child: Row(children: [
                    Icon(Icons.download_outlined,
                        size: 20, color: _iconNeutral),
                    const SizedBox(width: 12),
                    const Text("Enregistrer"),
                  ])),
            if (hasText)
              PopupMenuItem(
                  value: 'copy',
                  child: Row(children: [
                    Icon(Icons.copy, size: 20, color: _iconNeutral),
                    const SizedBox(width: 12),
                    const Text("Copier"),
                  ])),
            PopupMenuItem(
                value: 'pin',
                child: Row(children: [
                  Icon(
                      _pinnedMessageId == m.id
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 20,
                      color: _accent),
                  const SizedBox(width: 12),
                  Text(_pinnedMessageId == m.id ? "Détacher" : "Épingler"),
                ])),
            if (mine && m.type == 'TEXT')
              PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 20, color: _positive),
                    const SizedBox(width: 12),
                    const Text("Modifier"),
                  ])),
          ],
        ),
      ],
    );
  }

  void _openAvatarViewer() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AvatarViewerScreen(
            name: widget.title, avatarUrl: widget.avatarUrl)));
  }

  void _openGroupInfo() {
    if (!widget.isGroup) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupInfoScreen(
            convId: widget.convId,
            title: widget.title,
            avatarUrl: widget.avatarUrl,
            members: widget.memberNames.entries
                .map((e) => {
                      'id': e.key,
                      'pseudo': e.value,
                      'publicNumber': '',
                      'avatarUrl': null,
                      'isOnline': 0,
                      'role': 'MEMBER'
                    })
                .toList())));
  }

  void _openContactInfo() {
    if (widget.isGroup) return;
    final otherId = widget.otherUserId;
    if (otherId == null) {
      _openAvatarViewer();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ContactInfoScreen(
            userId: otherId,
            name: widget.title,
            publicNumber: widget.otherPublicNumber ?? "",
            avatarUrl: widget.avatarUrl,
            statusMsg: widget.otherStatusMsg,
            convId: widget.convId,
            contactId: widget.contactId,
            isBlocked: widget.isBlocked,
            isOnline: widget.otherIsOnline == 1,
            lastSeen: widget.otherLastSeen)));
  }

  // ══════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // watch (et non read) : reconstruit la vue dès que l'utilisateur est chargé,
    // garantissant le bon alignement des bulles même si l'auth arrive après
    // l'ouverture de la conversation. Fallback sur _myId par sécurité.
    final myId = context.watch<AuthController>().user?.id ?? _myId;
    return Scaffold(
      appBar: _searchMode
          ? _searchAppBar()
          : (_selectedMessageId != null &&
                  _findMessage(_selectedMessageId) != null
              ? _selectionAppBar(_findMessage(_selectedMessageId)!)
              : _whatsappAppBar()),
      body: MotifBackground(
        overlayOpacity: 0.85,
        child: Column(children: [
          _pinnedBanner(),
          Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: _accent))
                  : _combined.isEmpty
                      ? Center(child: Text(tr(context, 'no_messages')))
                      // 🔴 **LISTE ANCRÉE EN BAS** (`reverse: true`), corrigé le
                      // 17/08/2026 sur preuve de `logcat`.
                      //
                      // Ancrée en haut, la liste gardait son offset pendant que ce
                      // qui la précède changeait — donc le contenu affiché sautait.
                      // Deux mesures relevées sur le téléphone du user :
                      //   • « liste recomposée — 67 → 33 éléments » pendant qu'il
                      //     ne touchait à rien : 34 éléments disparus AU-DESSUS de
                      //     sa position, et tout ce qui suit remonte d'autant ;
                      //   • à l'ouverture du clavier, `offset` reste à 7205.3
                      //     pendant que la fenêtre passe de 374 à 253 points.
                      //
                      // Inversée, l'origine du défilement est le DERNIER message :
                      // le point fixe devient celui que l'utilisateur regarde, et
                      // tout changement plus ancien se produit hors de sa vue —
                      // exactement ce que fait WhatsApp. Le fond n'est plus une
                      // valeur à recalculer (`maxScrollExtent`, qui bougeait à
                      // chaque image), c'est **zéro**.
                      : ListView.builder(
                          controller: _scrollCtrl,
                          reverse: true,
                          padding: const EdgeInsets.all(12),
                          itemCount: _combined.length,
                          itemBuilder: (_, iAffichage) {
                            // L'ordre des données reste chronologique : seule la
                            // lecture s'inverse. Tout le reste de l'écran (dates,
                            // pagination, saut vers un message) continue de
                            // raisonner en indices chronologiques.
                            final i = _combined.length - 1 - iAffichage;
                            final item = _combined[i];
                            final widgets = <Widget>[];
                            if (_needsDateSeparatorCombined(i)) {
                              widgets.add(
                                  _dateChip(_dateLabel(_dateOfCombined(item))));
                            }
                            if (item is Message) {
                              widgets.add(_bubble(item, item.senderId == myId));
                            } else if (item is GroupeMedias) {
                              widgets.add(
                                  _groupBubble(item, item.senderId == myId));
                            } else if (item is CallRecord) {
                              widgets.add(_callBubbleInChat(item));
                            }
                            return Column(children: widgets);
                          })),
          if (!widget.isGroup)
            ActivityIndicatorBar(
                typing: _peerTyping, recording: _peerRecording),
          _composer(),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // BUBBLE — WhatsApp previews + grille multi-médias
  // ══════════════════════════════════════════════
  Widget _bubble(Message m, bool mine) {
    // Message système (ex. « Messages éphémères activés ») : pastille centrée.
    if (m.type == "SYSTEM") {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _dark
                ? AlanyaColors.gold.withValues(alpha: 0.14)
                : AlanyaColors.gold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer_outlined, size: 15, color: _iconNeutral),
            const SizedBox(width: 6),
            Flexible(
              child: Text(m.content ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: _iconNeutral)),
            ),
          ]),
        ),
      );
    }
    final hasMedia = m.media.isNotEmpty;
    final isMultiMedia = hasMedia && m.media.length > 1;
    // Type EFFECTIF, et non celui annoncé par le message.
    //
    // Le client web omettait « video » dans sa table de conversion : les
    // vidéos ont été enregistrées avec le type TEXT. Corriger le web ne répare
    // pas les messages déjà en base — sans ce repli, ils continueraient
    // d'afficher « [TEXT] » pour toujours.
    //
    // Dès qu'un média est présent, son type MIME fait autorité : il vient du
    // fichier lui-même, là où le type du message vient d'un client.
    final effectif = _typeEffectif(m);
    final isImage = !isMultiMedia && effectif == "IMAGE" && hasMedia;
    final isVideo = !isMultiMedia && effectif == "VIDEO" && hasMedia;
    final isFile = !isMultiMedia && effectif == "FILE" && hasMedia;
    final isAudio = !isMultiMedia && effectif == "AUDIO" && hasMedia;
    // Fiche de contact : la charge est dans `content`, le média éventuel n'est
    // que la photo. Une charge illisible retombe sur la bulle texte, qui
    // affichera au moins quelque chose plutôt qu'une carte vide.
    final contactsPartages =
        effectif == "CONTACT" ? _contactsDe(m) : const <SharedContact>[];
    final isContact = contactsPartages.isNotEmpty;
    // Même principe pour la position : charge illisible → bulle texte, jamais
    // une carte vide au milieu de l'océan.
    final positionPartagee =
        effectif == "LOCATION" ? positionDepuisContenu(m.content) : null;
    final senderLabel = widget.isGroup && !mine
        ? (widget.memberNames[m.senderId] ?? "Membre")
        : null;
    final isHighlighted =
        _highlightedMessageId == m.id || _selectedMessageId == m.id;
    final isGrid = isMultiMedia; // 2+ médias → grille

    return Align(
      key: _messageKeys.putIfAbsent(m.id, () => GlobalKey()),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (senderLabel != null)
              Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(senderLabel,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _positive))),
            _SwipeToReply(
              onReply: () => _setReplyTo(m),
              child: GestureDetector(
                onLongPress: () => _openMessageActions(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: (isImage || isVideo || isGrid)
                      ? const EdgeInsets.all(3)
                      : const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                  constraints: const BoxConstraints(maxWidth: 280),
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? AlanyaColors.gold
                            .withValues(alpha: _dark ? 0.22 : 0.3)
                        : (mine ? _sentBubbleColor : _recvBubbleColor),
                    // Forme WhatsApp : petite queue en haut du côté de l'expéditeur
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(mine ? 12 : 0),
                      topRight: Radius.circular(mine ? 0 : 12),
                      bottomLeft: const Radius.circular(12),
                      bottomRight: const Radius.circular(12),
                    ),
                    border: mine
                        ? null
                        : Border.all(
                            color:
                                isHighlighted ? AlanyaColors.gold : _hairline),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.replyToId != null && !m.isDeleted)
                          _replyPreviewHeader(m, mine),
                        m.isDeleted
                            ? _deletedBubble(m, mine)
                            // Envoi en cours ou échoué : la bulle montre la vignette
                            // LOCALE et la progression, le média n'existant pas encore
                            // côté serveur. Passe avant tout le reste, sinon le message
                            // optimiste (sans média) retomberait sur la bulle texte.
                            : _envois[m.id] != null
                                ? SendingMediaBubble(
                                    envoi: _envois[m.id]!,
                                    legende: m.content,
                                    isMe: mine,
                                    onReessayer: () =>
                                        _reessayerEnvoi(_envois[m.id]!),
                                    onAbandonner: () =>
                                        _abandonneEnvoi(_envois[m.id]!),
                                  )
                                : isContact
                                    ? ContactBubble(
                                        contacts: contactsPartages,
                                        actions: ContactBubbleActions(
                                          onOuvrirDiscussion:
                                              _ouvrirDiscussionContact,
                                          onAppeler: _appelerContact,
                                          onAjouter: _ajouterContactAlanya,
                                        ),
                                        onLongPress: () =>
                                            _openMessageActions(m),
                                        timestamp: _time(m.createdAt),
                                        statusWidget: mine
                                            ? _statusTicks(
                                                m.status, Colors.white70)
                                            : null,
                                        isMe: mine,
                                      )
                                    : positionPartagee != null
                                        ? LocationBubble(
                                            position: positionPartagee,
                                            onLongPress: () =>
                                                _openMessageActions(m),
                                            timestamp: _time(m.createdAt),
                                            statusWidget: mine
                                                ? _statusTicks(
                                                    m.status, Colors.white70)
                                                : null,
                                            isMe: mine,
                                          )
                                        : isGrid
                                            ? _grilleAvecLegende(
                                                medias: m.media,
                                                legende: m.content,
                                                horodatage: _time(m.createdAt),
                                                statut: mine
                                                    ? _statusTicks(
                                                        m.status, Colors.white)
                                                    : null,
                                                mine: mine,
                                                onTapMedia: (i) =>
                                                    _openGallery(m.media[i].id),
                                                onLongPressMedia: (_) =>
                                                    _openMessageActions(m),
                                              )
                                            : isImage
                                                ? ImageBubble(
                                                    imageUrl:
                                                        '$_baseUrl${m.media.first.url}',
                                                    token: _token,
                                                    caption: m.content,
                                                    onTap: () =>
                                                        _openImageViewer(m),
                                                    onLongPress: () =>
                                                        _openMessageActions(m),
                                                    timestamp:
                                                        _time(m.createdAt),
                                                    statusWidget: mine
                                                        ? _statusTicks(m.status,
                                                            Colors.white)
                                                        : null,
                                                    isMe: mine,
                                                  )
                                                : isVideo
                                                    ? VideoBubble(
                                                        videoUrl:
                                                            '$_baseUrl${m.media.first.url}',
                                                        token: _token,
                                                        duration: m.media.first
                                                            .durationMs,
                                                        caption: m.content,
                                                        onTap: () =>
                                                            _openVideoViewer(m),
                                                        onLongPress: () =>
                                                            _openMessageActions(
                                                                m),
                                                        timestamp:
                                                            _time(m.createdAt),
                                                        statusWidget: mine
                                                            ? _statusTicks(
                                                                m.status,
                                                                Colors.white)
                                                            : null,
                                                        isMe: mine,
                                                      )
                                                    : isFile
                                                        ? DocumentBubble(
                                                            fileName: m
                                                                    .media
                                                                    .first
                                                                    .filename ??
                                                                tr(context,
                                                                    'file'),
                                                            fileSize: m
                                                                .media
                                                                .first
                                                                .sizeBytes,
                                                            mimeType: m.media
                                                                .first.mimeType,
                                                            pdfUrl:
                                                                '$_baseUrl${m.media.first.url}',
                                                            token: _token,
                                                            onTap: () {
                                                              final media =
                                                                  m.media.first;
                                                              final isPdf = media
                                                                          .mimeType ==
                                                                      "application/pdf" ||
                                                                  _ext(media.filename ??
                                                                              "")
                                                                          .toLowerCase() ==
                                                                      "pdf";
                                                              isPdf
                                                                  ? _openPdfViewer(
                                                                      m)
                                                                  : _openDocument(
                                                                      media);
                                                            },
                                                            onLongPress: () =>
                                                                _openMessageActions(
                                                                    m),
                                                            timestamp: _time(
                                                                m.createdAt),
                                                            statusWidget: mine
                                                                ? _statusTicks(
                                                                    m.status,
                                                                    mine
                                                                        ? Colors
                                                                            .white70
                                                                        : _muted45)
                                                                : null,
                                                            isMe: mine,
                                                          )
                                                        : isAudio
                                                            ? AudioBubble(
                                                                url: _mediaUrl(m
                                                                    .media
                                                                    .first),
                                                                duration: m
                                                                    .media
                                                                    .first
                                                                    .durationMs,
                                                                onTap: () => InlineAudioPlayer.toggle(
                                                                    _mediaUrl(m
                                                                        .media
                                                                        .first),
                                                                    totalDuration: m.media.first.durationMs !=
                                                                            null
                                                                        ? Duration(
                                                                            milliseconds:
                                                                                m.media.first.durationMs!)
                                                                        : null),
                                                                timestamp: _time(
                                                                    m.createdAt),
                                                                statusWidget: mine
                                                                    ? _statusTicks(
                                                                        m
                                                                            .status,
                                                                        mine
                                                                            ? Colors.white70
                                                                            : _muted45)
                                                                    : null,
                                                                isMe: mine,
                                                              )
                                                            : _textBubble(
                                                                m, mine),
                      ]),
                ),
              ),
            ),
            if (m.reactions.isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -14),
                child: _reactionsChips(m, mine),
              ),
          ]),
    );
  }

  /// Grille de médias, avec sa légende SOUS la grille quand il y en a une.
  ///
  /// 🐛 **La légende d'un envoi multiple n'était JAMAIS affichée** : la branche
  /// « grille » rendait `MediaGrid` seul et ignorait `m.content`. On pouvait donc
  /// envoyer trois photos avec un commentaire, et il disparaissait des deux
  /// côtés. C'est ce que ce point unique répare.
  ///
  /// Quand il y a une légende, l'horodatage passe SOUS le texte au lieu de la
  /// pastille posée sur l'image : sur une photo, il doit rester lisible ; sous du
  /// texte, il se lit comme dans une bulle ordinaire — c'est ce que fait
  /// WhatsApp.
  Widget _grilleAvecLegende({
    required List<MessageMedia> medias,
    required String? legende,
    required String horodatage,
    required Widget? statut,
    required bool mine,
    required void Function(int index) onTapMedia,
    required void Function(int index) onLongPressMedia,
  }) {
    final aLegende = (legende ?? '').isNotEmpty;
    final items = medias
        .map((media) => MediaGridItem(
              url: media.url,
              mimeType: media.mimeType,
              fileName: media.filename,
              sizeBytes: media.sizeBytes,
              durationMs: media.durationMs,
            ))
        .toList();

    final grille = MediaGrid(
      items: items,
      baseUrl: _baseUrl,
      token: _token,
      onItemTap: (i) {
        if (i >= 0 && i < medias.length) onTapMedia(i);
      },
      onItemLongPress: (i) {
        if (i >= 0 && i < medias.length) onLongPressMedia(i);
      },
      // « +N » ouvre la visionneuse SUR le média touché, et non au début.
      onMoreTap: (i) {
        if (i >= 0 && i < medias.length) onTapMedia(i);
      },
      timestamp: aLegende ? null : horodatage,
      statusWidget: aLegende ? null : statut,
      isMe: mine,
    );

    if (!aLegende) return grille;

    final onText = _bubbleTextColor(mine);
    final onSub = mine ? Colors.white70 : _muted45;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      grille,
      const SizedBox(height: 5),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text.rich(
          TextSpan(children: spansWhatsApp(legende!)),
          style: TextStyle(color: onText, fontSize: 14.5),
        ),
      ),
      const SizedBox(height: 2),
      Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Spacer(),
          Text(horodatage, style: TextStyle(fontSize: 11, color: onSub)),
          if (statut != null) ...[const SizedBox(width: 3), statut],
        ]),
      ),
    ]);
  }

  /// Bulle d'un GROUPE de messages de médias — voir `groupe_medias.dart`.
  ///
  /// L'appui long agit sur le message du média touché, jamais sur le groupe :
  /// « répondre » ou « supprimer » n'a de sens que pour un message.
  Widget _groupBubble(GroupeMedias groupe, bool mine) {
    final medias = groupe.medias;
    final senderLabel = widget.isGroup && !mine
        ? (widget.memberNames[groupe.senderId] ?? "Membre")
        : null;
    // Une grille regroupe PLUSIEURS messages : elle s'illumine dès que l'un
    // d'eux est la cible. Sans cela, sauter vers une photo citée amenait au bon
    // endroit sans que rien ne s'allume — la grille ignorait la surbrillance,
    // qui n'était traitée que pour les bulles individuelles.
    final enSurbrillance = groupe.messages.any(
        (m) => _highlightedMessageId == m.id || _selectedMessageId == m.id);

    return Align(
      // La clé du PREMIER message du groupe : c'est elle que cherche le saut
      // vers un message cité pour affiner sa position.
      key:
          _messageKeys.putIfAbsent(groupe.messages.first.id, () => GlobalKey()),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (senderLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(senderLabel,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _positive)),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(3),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: enSurbrillance
                  ? AlanyaColors.gold.withValues(alpha: _dark ? 0.22 : 0.3)
                  : (mine ? _sentBubbleColor : _recvBubbleColor),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(mine ? 12 : 0),
                topRight: Radius.circular(mine ? 0 : 12),
                bottomLeft: const Radius.circular(12),
                bottomRight: const Radius.circular(12),
              ),
              border: mine
                  ? null
                  : Border.all(
                      color: enSurbrillance ? AlanyaColors.gold : _hairline),
            ),
            child: _grilleAvecLegende(
              medias: medias,
              // Un message porteur d'une légende n'est jamais regroupé : il n'y
              // a donc pas de légende à afficher ici, par construction.
              legende: null,
              horodatage: _time(groupe.date),
              statut: mine ? _statusTicks(groupe.statut, Colors.white) : null,
              mine: mine,
              onTapMedia: (i) => _openGallery(medias[i].id),
              onLongPressMedia: (i) {
                final msg = groupe.messageDuMedia(i);
                if (msg != null) _openMessageActions(msg);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pastilles de réactions sous la bulle : agrège par emoji (emoji + compteur),
  /// met en évidence la mienne. Toucher une pastille bascule ma réaction.
  Widget _reactionsChips(Message m, bool mine) {
    final Map<String, int> counts = {};
    String? myEmoji;
    for (final r in m.reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
      if (r.userId == _myId) myEmoji = r.emoji;
    }
    return Padding(
      padding: EdgeInsets.only(
          top: 1, bottom: 3, left: mine ? 0 : 6, right: mine ? 6 : 0),
      child: Wrap(
        spacing: 4,
        children: counts.entries.map((e) {
          final isMine = e.key == myEmoji;
          return GestureDetector(
            onTap: () => _react(m, e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isMine ? _accent.withValues(alpha: 0.15) : _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isMine ? _accent.withValues(alpha: 0.5) : _hairline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(e.key, style: const TextStyle(fontSize: 13)),
                if (e.value > 1) ...[
                  const SizedBox(width: 3),
                  Text("${e.value}",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _dark
                              ? AlanyaColors.craie
                              : AlanyaColors.grey700)),
                ],
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _deletedBubble(Message m, bool mine) {
    final onSub = mine ? Colors.white70 : _muted45;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 14, color: onSub),
        const SizedBox(width: 6),
        Text(tr(context, 'message_deleted'),
            style: TextStyle(
                fontSize: 13, fontStyle: FontStyle.italic, color: onSub)),
      ]),
      const SizedBox(height: 2),
      Text(_time(m.createdAt), style: TextStyle(fontSize: 10, color: onSub)),
    ]);
  }

  // ══ TEXT BUBBLE AVEC LINK PREVIEW ══
  /// Type réel d'un message, déduit du MIME de son premier média.
  ///
  /// Sans média, le type annoncé est conservé tel quel. Avec média, le MIME
  /// prime : il décrit le fichier, alors que le type du message n'est qu'une
  /// affirmation du client qui l'a envoyé — et cette affirmation a été fausse
  /// pour toutes les vidéos venues du web.
  String _typeEffectif(Message m) {
    // ⚠️ EXCEPTION AVANT TOUT LE RESTE : un CONTACT peut porter la photo du
    // contact comme média. Laisser le MIME primer afficherait cette photo en
    // grand à la place de la fiche — la règle du MIME existe pour rattraper des
    // messages MAL ÉTIQUETÉS, pas pour contredire un type structuré, dont la
    // charge utile est dans `content`.
    if (m.type == "CONTACT" || m.type == "LOCATION") return m.type;
    if (m.media.isEmpty) return m.type;
    final mime = m.media.first.mimeType;
    if (mime.startsWith('image/')) return 'IMAGE';
    if (mime.startsWith('video/')) return 'VIDEO';
    if (mime.startsWith('audio/')) return 'AUDIO';
    // MIME inconnu : un message porteur d'un fichier n'est en tout cas pas du
    // texte, sinon il retomberait sur la bulle texte et afficherait « [TEXT] ».
    return m.type == 'TEXT' ? 'FILE' : m.type;
  }

  Widget _textBubble(Message m, bool mine) {
    final translated = _translations[m.id];
    final isTranslating = _translating.contains(m.id);
    final onTextColor = _bubbleTextColor(mine);
    final onSubColor = mine ? Colors.white70 : _muted45;
    return GestureDetector(
      onTap: m.type == 'TEXT' && (m.content ?? '').isNotEmpty
          ? () => _translateMessage(m)
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Mise en forme façon WhatsApp : *gras*, _italique_, ~barré~ et
        // ```chasse fixe```. Les marqueurs disparaissent à l'affichage ; le
        // contenu stocké et envoyé reste le texte brut avec ses marqueurs, ce
        // qui garde le message lisible pour tout client qui ne les interprète
        // pas.
        (() {
          var displayText = m.content ?? "[${m.type}]";
          if (!m.isDeleted && extractGpsCoords(displayText) != null) {
            // On retire du texte AFFICHÉ ce que la carte montre déjà. Les
            // motifs retirés sont EXACTEMENT ceux que `extractGpsCoords`
            // reconnaît — le couple de décimaux nu n'en fait plus partie,
            // sinon un montant cité dans le message disparaissait de
            // l'affichage sans que rien ne l'explique.
            displayText = displayText
                .replaceAll(
                    RegExp(r'\(\s*(-?\d+\.\d{2,})\s*,\s*(-?\d+\.\d{2,})\s*\)'),
                    '')
                .replaceAll(
                    RegExp(
                        r'(?:google\.\w+/maps|maps\.google\.\w+|goo\.gl/maps)\S*'),
                    '')
                .replaceAll(
                    RegExp(r'geo:\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)'), '')
                .replaceAll(RegExp(r'\(\s*\)'), '')
                .replaceAll(RegExp(r'\s{2,}'), ' ')
                .trim();
          }
          if (!m.isDeleted && displayText.contains('[')) {
            displayText =
                displayText.replaceAll(RegExp(r'\[([^\]]+)\]'), '').trim();
          }
          return displayText.isNotEmpty
              ? Text.rich(
                  TextSpan(children: spansWhatsApp(displayText)),
                  style: TextStyle(color: onTextColor),
                )
              : const SizedBox.shrink();
        })(),
        if ((m.content ?? '').isNotEmpty) ...[
          buildLinkPreview(m.content!, mine),
          (() {
            final gps = extractGpsCoords(m.content!);
            return gps != null
                ? GpsPreview(lat: gps.lat, lng: gps.lng, isMe: mine)
                : const SizedBox.shrink();
          })(),
        ],
        if (!m.isDeleted && (m.content ?? '').isNotEmpty) ...[
          (() {
            final buttonMatches =
                RegExp(r'\[([^\]]+)\]').allMatches(m.content!);
            if (buttonMatches.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: buttonMatches.map((bm) {
                  final btnTitle = bm.group(1) ?? '';
                  return GestureDetector(
                    onTap: () {
                      setState(() => _replyTo = m);
                      _inputCtrl.text = btnTitle;
                      _send();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: mine
                            ? Colors.white.withOpacity(0.2)
                            : _accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: mine ? Colors.white54 : _accent),
                      ),
                      child: Text(
                        btnTitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mine ? Colors.white : _accent,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          })(),
        ],
        if (translated != null) ...[
          const SizedBox(height: 6),
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color:
                      mine ? Colors.white.withOpacity(0.15) : _quoteBgRecv(0.7),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.translate, size: 12, color: onSubColor),
                      const SizedBox(width: 4),
                      Text(tr(context, 'translated'),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: onSubColor))
                    ]),
                    const SizedBox(height: 2),
                    Text(translated,
                        style: TextStyle(
                            fontSize: 13,
                            color: onTextColor,
                            fontStyle: FontStyle.italic)),
                  ])),
        ],
        if (isTranslating) ...[
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: onSubColor)),
            const SizedBox(width: 6),
            Text(tr(context, 'translating'),
                style: TextStyle(fontSize: 10, color: onSubColor))
          ]),
        ],
        if (!isTranslating && translated == null && m.type == 'TEXT')
          Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(tr(context, 'translate'),
                  style: TextStyle(
                      fontSize: 10,
                      color: onSubColor.withOpacity(0.8),
                      fontStyle: FontStyle.italic))),
        const SizedBox(height: 2),
        _timestampRow(m, mine, onSubColor),
      ]),
    );
  }

  Future<void> _translateMessage(Message m) async {
    final text = (m.content ?? '').trim();
    if (text.isEmpty) return;
    final locale = context.read<LocaleController>().languageCode;
    if (_translations.containsKey(m.id)) {
      setState(() => _translations.remove(m.id));
      return;
    }
    if (_translating.contains(m.id)) return;
    setState(() => _translating.add(m.id));
    try {
      final translated = await _translateService.translate(
          text: text, target: locale, source: 'auto');
      if (!mounted) return;
      setState(() => _translations[m.id] = translated);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'translation_failed'))));
    } finally {
      if (mounted) setState(() => _translating.remove(m.id));
    }
  }

  // ══ TIME / DATE ══
  String _time(DateTime d) {
    final l = d.toLocal();
    return "${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}";
  }

  String _lastSeenLabel(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "vu à l'instant";
    if (diff.inMinutes < 60) return "vu il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "vu il y a ${diff.inHours}h";
    return "vu il y a ${diff.inDays}j";
  }

  Widget _dateChip(String label) {
    return Center(
        child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
                color: _pillBg, borderRadius: BorderRadius.circular(10)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color:
                        _dark ? AlanyaColors.craie2 : AlanyaColors.grey600))));
  }

  String _dateLabel(DateTime d) {
    final l = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(l.year, l.month, l.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return "Hier";
    if (diff < 7) {
      const days = [
        'Lundi',
        'Mardi',
        'Mercredi',
        'Jeudi',
        'Vendredi',
        'Samedi',
        'Dimanche'
      ];
      return days[l.weekday - 1];
    }
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    ];
    return "${l.day} ${months[l.month - 1]} ${l.year}";
  }

  bool _needsDateSeparator(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1].createdAt.toLocal();
    final curr = _messages[index].createdAt.toLocal();
    return prev.year != curr.year ||
        prev.month != curr.month ||
        prev.day != curr.day;
  }

  // ══════════════════════════════════════════════
  // COMPOSER (inchangé)
  // ══════════════════════════════════════════════
  Widget _composer() {
    if (_recordLocked) {
      return SafeArea(
          top: false,
          child: Container(
              padding: const EdgeInsets.all(8),
              color: _composerBg,
              child: Row(children: [
                GestureDetector(
                    onTap: () => _stopVoiceRecord(cancel: true),
                    child: CircleAvatar(
                        backgroundColor: _dark
                            ? AlanyaColors.erreurNuit
                            : Colors.red.shade400,
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white))),
                const SizedBox(width: 8),
                Expanded(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                            color: _recordBg,
                            borderRadius: BorderRadius.circular(24)),
                        child: Row(children: [
                          Icon(Icons.fiber_manual_record,
                              color: _danger, size: 14),
                          const SizedBox(width: 8),
                          Text(_formatDuration(_recordDuration),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _dark
                                      ? AlanyaColors.erreurNuit
                                      : Colors.red.shade700,
                                  fontSize: 15)),
                          const Spacer(),
                          Icon(Icons.lock,
                              color: _dark
                                  ? AlanyaColors.erreurNuit
                                  : Colors.red.shade400,
                              size: 18),
                          const SizedBox(width: 4),
                          Text(tr(context, 'recording_locked'),
                              style: TextStyle(fontSize: 13, color: _muted)),
                        ]))),
                const SizedBox(width: 8),
                GestureDetector(
                    onTap: _uploading ? null : () => _stopVoiceRecord(),
                    child: CircleAvatar(
                        backgroundColor: _accent,
                        child: const Icon(Icons.send, color: Colors.white))),
              ])));
    }
    return SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_editing != null)
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: _composerBg,
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 18, color: _positive),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text("Modifier le message",
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _positive)),
                        Text(_editing!.content ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: _muted)),
                      ])),
                  GestureDetector(
                      onTap: _cancelEdit,
                      child: Icon(Icons.close, size: 20, color: _muted)),
                ])),
          if (_replyTo != null && _editing == null)
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: _composerBg,
                child: Row(children: [
                  Container(
                      width: 3,
                      height: 32,
                      decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            _replyTo!.senderId == _myId
                                ? tr(context, 'you')
                                : (widget.memberNames[_replyTo!.senderId] ??
                                    tr(context, 'reply_to')),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _accent)),
                        Text(
                            _replyTo!.isDeleted
                                ? tr(context, 'message_deleted')
                                : (_replyTo!.content ??
                                    (_replyTo!.media.isNotEmpty
                                        ? '📎 ${_replyTo!.media.first.filename ?? tr(context, 'file')}'
                                        : '...')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: _muted)),
                      ])),
                  GestureDetector(
                      onTap: () => setState(() => _replyTo = null),
                      child: Icon(Icons.close, size: 20, color: _muted)),
                ])),
          Container(
              padding: const EdgeInsets.all(8),
              color: _composerBg,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _formatBar(),
                Row(children: [
                  // Ordre repris de la maquette : TOUT est dans le champ — smiley contre
                  // le bord gauche, « A » et trombone contre le bord droit. Seul le
                  // bouton rond reste à l'extérieur. Le smiley et le trombone étaient
                  // auparavant posés hors du champ, où ils lui volaient de la largeur.
                  Expanded(
                      child: _recording
                          ? _recordingBar()
                          : TextField(
                              controller: _inputCtrl,
                              focusNode: _inputFocus,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onChanged: _onInputChanged,
                              onSubmitted: (_) => _send(),
                              // Second chemin, celui de WhatsApp : sélectionner du texte, puis
                              // choisir la mise en forme dans le menu contextuel, à la suite de
                              // Couper / Copier / Coller. On repart des entrées natives plutôt que
                              // de les remplacer, sinon on perdrait le presse-papiers.
                              //
                              // Les libellés sont résolus avec le `context` de l'écran, pas celui
                              // du constructeur de menu : la traduction passe par un Provider, et
                              // l'observer depuis un contexte plus profond n'apporterait rien.
                              contextMenuBuilder:
                                  (menuContext, editableState) =>
                                      AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: editableState.contextMenuAnchors,
                                buttonItems: [
                                  ...editableState.contextMenuButtonItems,
                                  for (final m in MarqueurWhatsApp.tous)
                                    ContextMenuButtonItem(
                                      label: tr(context, m.cleTraduction),
                                      onPressed: () {
                                        editableState.hideToolbar();
                                        appliqueMarqueur(_inputCtrl, m.code);
                                      },
                                    ),
                                ],
                              ),
                              decoration: InputDecoration(
                                hintText: tr(context, 'write_message'),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                // Smiley À L'INTÉRIEUR du champ, contre le bord gauche.
                                prefixIcon: IconButton(
                                  tooltip: "Emojis",
                                  icon: Icon(
                                      _emojiPanelOpen
                                          ? Icons.keyboard
                                          : Icons.emoji_emotions_outlined,
                                      color: _emojiPanelOpen
                                          ? _accent
                                          : _iconNeutral),
                                  onPressed: () {
                                    setState(() =>
                                        _emojiPanelOpen = !_emojiPanelOpen);
                                    // Le panneau et le clavier système se disputent le bas de
                                    // l'écran : ouvrir l'un doit refermer l'autre, sinon le
                                    // composeur remonte deux fois et masque la conversation.
                                    if (_emojiPanelOpen) {
                                      FocusScope.of(context).unfocus();
                                    } else {
                                      _inputFocus.requestFocus();
                                    }
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 40, minHeight: 40),
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                    minWidth: 44, minHeight: 40),
                                // Bouton « A » À L'INTÉRIEUR du champ, contre le bord droit. Il
                                // était auparavant posé à côté du trombone, hors du champ : il
                                // volait de la largeur à la saisie et se lisait comme une action
                                // d'envoi de plus, au lieu d'un réglage du texte en cours.
                                // « A » puis le trombone, tous deux À L'INTÉRIEUR du champ contre
                                // le bord droit. Le trombone les rejoint : posé à gauche, hors du
                                // champ, il volait de la largeur à la saisie.
                                suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: "Mise en forme",
                                        icon: _iconeFormatA(_formatBarOpen
                                            ? _accent
                                            : _iconNeutral),
                                        onPressed: () => setState(() =>
                                            _formatBarOpen = !_formatBarOpen),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 36, minHeight: 36),
                                      ),
                                      IconButton(
                                        tooltip: tr(context, 'attach_file'),
                                        icon: _uploading
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : Icon(Icons.attach_file,
                                                color: _iconNeutral),
                                        onPressed: _uploading
                                            ? null
                                            : _pickAndSendFile,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 36, minHeight: 36),
                                      ),
                                      const SizedBox(width: 4),
                                    ]),
                                // Sans ces contraintes, l'icône suffixe impose sa hauteur minimale
                                // de 48 px au champ, qui grossit alors visiblement.
                                suffixIconConstraints: const BoxConstraints(
                                    minWidth: 40, minHeight: 40),
                              ),
                            )),
                  const SizedBox(width: 8),
                  // UN SEUL bouton rond, qui bascule. Le micro et l'envoi s'affichaient
                  // tous les deux en permanence : deux boutons dont un seul avait du sens
                  // à un instant donné.
                  _hasText && !_recording
                      ? CircleAvatar(
                          backgroundColor: _accent,
                          child: IconButton(
                              tooltip: tr(context, 'send'),
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: _sending ? null : _send))
                      : _micButton(),
                ]),
                if (_emojiPanelOpen && !_recording) _emojiPanel(),
              ])),
        ]));
  }

  /// « A » souligné d'une barre épaisse, symbole de la mise en forme.
  ///
  /// Dessiné plutôt que pris dans `Icons.text_format` : le glyphe Material
  /// porte un trait d'un pixel qui se perd à cette taille. Ici la barre fait
  /// 3 px et toute la largeur de la lettre, comme sur la maquette. Elle prend
  /// la couleur de la lettre, donc elle vire à l'accent quand la barre de mise
  /// en forme est dépliée.
  Widget _iconeFormatA(Color couleur) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "A",
          style: TextStyle(
            color: couleur,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 2),
        Container(width: 17, height: 3, color: couleur),
      ],
    );
  }

  /// Emojis les plus courants, insérés dans le champ au clic.
  ///
  /// Volontairement une grille figée et non un vrai clavier emoji : rien dans
  /// le projet n'en fournissait, et une liste courte couvre l'essentiel sans
  /// ajouter de dépendance. Les emojis sont du TEXTE — ils partent dans un
  /// message normal, sans rien changer au protocole.
  static const List<String> _emojisCourants = [
    "😀",
    "😂",
    "🙂",
    "😍",
    "😘",
    "😎",
    "🤔",
    "😴",
    "😢",
    "😭",
    "😡",
    "🥳",
    "👍",
    "👎",
    "👏",
    "🙏",
    "❤️",
    "🔥",
    "✨",
    "🎉",
    "💯",
    "✅",
    "❌",
    "📞",
  ];

  Widget _emojiPanel() {
    return Container(
      height: 180,
      margin: const EdgeInsets.only(top: 6),
      child: GridView.count(
        crossAxisCount: 8,
        children: [
          for (final e in _emojisCourants)
            InkWell(
              onTap: () => _insereEmoji(e),
              child:
                  Center(child: Text(e, style: const TextStyle(fontSize: 24))),
            ),
        ],
      ),
    );
  }

  Widget _recordingBar() {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: _recordBg, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          Icon(Icons.fiber_manual_record, color: _danger, size: 14),
          const SizedBox(width: 8),
          Text(_formatDuration(_recordDuration),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _dark ? AlanyaColors.erreurNuit : Colors.red.shade700,
                  fontSize: 15)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(tr(context, 'slide_up_to_lock'),
                  style: TextStyle(fontSize: 13, color: _muted),
                  textAlign: TextAlign.center)),
          Icon(Icons.keyboard_arrow_up,
              color: _dark ? AlanyaColors.craie2 : Colors.black38, size: 20),
        ]));
  }

  Widget _micButton() {
    // Le micro grandit dès l'appui et garde SA couleur. Il virait au rouge
    // instantanément, ce qui donnait l'impression d'une alerte plutôt que d'un
    // enregistrement en cours — WhatsApp ne change pas la couleur du bouton,
    // c'est la barre du composeur qui signale l'enregistrement.
    final actif = _micHeld || _recording;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) {
        setState(() => _micHeld = true);
        _startVoiceRecord();
      },
      onLongPressMoveUpdate: (details) {
        if (details.offsetFromOrigin.dy < -60 && _recording && !_recordLocked) {
          // `_micHeld` remis à faux ICI, et c'est indispensable. Le verrouillage
          // fait basculer _composer() sur une autre branche, qui retire ce
          // GestureDetector de l'arbre : supprimé en pleine gestuelle, il ne
          // déclenchera jamais son onLongPressEnd. Sans cette ligne, _micHeld
          // restait vrai pour toujours et le micro demeurait agrandi après
          // l'envoi ou la suppression du vocal.
          setState(() {
            _recordLocked = true;
            _micHeld = false;
          });
        }
      },
      onLongPressEnd: (_) {
        setState(() => _micHeld = false);
        if (_recording && !_recordLocked) _stopVoiceRecord();
      },
      onLongPressCancel: () {
        setState(() => _micHeld = false);
        if (_recording && !_recordLocked) _stopVoiceRecord(cancel: true);
      },
      // AnimatedScale : la mise à l'échelle est une transformation de PEINTURE,
      // elle ne change pas la place occupée dans la rangée. Le micro déborde
      // par-dessus le composeur sans rien décaler, comme sur WhatsApp.
      child: AnimatedScale(
        scale: actif ? 2.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                backgroundColor: _dark
                    ? AlanyaColors.terracottaNuit
                    : AlanyaColors.chocolate,
                child: Icon(actif ? Icons.mic : Icons.mic_none,
                    color: Colors.white, size: 22),
              ),
              if (_recording && !_recordLocked) _indicateurCadenas(),
            ]),
      ),
    );
  }

  /// Cadenas au-dessus du micro, avec un chevron qui bat vers le haut.
  ///
  /// C'est l'affordance de WhatsApp : elle dit « glisse vers le haut » sans
  /// texte. Le battement est ce qui la rend lisible — un cadenas immobile
  /// ressemble à un état, pas à une invitation.
  ///
  /// Positionné en coordonnées NÉGATIVES dans un Stack en `Clip.none`, donc
  /// dessiné au-dessus du bouton sans agrandir sa zone tactile.
  Widget _indicateurCadenas() {
    return Positioned(
      top: -34,
      child: AnimatedBuilder(
        animation: _lockPulse,
        builder: (context, child) {
          // Le chevron monte de 4 px et s'estompe en haut de course ; le
          // cadenas, lui, reste fixe : c'est le point d'arrivée.
          final t = Curves.easeInOut.transform(_lockPulse.value);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: 0.35 + 0.65 * (1 - t),
              child: Transform.translate(
                offset: Offset(0, -4 * t),
                child: const Icon(Icons.keyboard_arrow_up,
                    color: Colors.white, size: 18),
              ),
            ),
            child!,
          ]);
        },
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_open, color: Colors.white, size: 14),
        ),
      ),
    );
  }

  /// Barre de mise en forme, dépliée par le bouton « A » du composeur.
  ///
  /// C'est le chemin « pour les pressés » : pas besoin de connaître les
  /// marqueurs. Un appui insère `**` et pose le curseur entre les deux ; si du
  /// texte est sélectionné, il est enveloppé à la place.
  ///
  /// `AnimatedSize` plutôt qu'un `if` sec : la barre pousse le champ de saisie
  /// vers le bas, et un saut brutal juste au-dessus du clavier se voit.
  Widget _formatBar() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: (!_formatBarOpen || _recording)
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final m in MarqueurWhatsApp.tous)
                    IconButton(
                      tooltip: tr(context, m.cleTraduction),
                      icon: Icon(m.icone, color: _iconNeutral),
                      onPressed: () {
                        appliqueMarqueur(_inputCtrl, m.code);
                        // Rendre le focus : l'appui sur l'icône le retire du
                        // champ, et le curseur qu'on vient de placer serait
                        // invisible sans clavier.
                        _inputFocus.requestFocus();
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

// ══════════════════════════════════════════════
// SWIPE TO REPLY
// ══════════════════════════════════════════════
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.onReply});
  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _dragExtent = 0;
  static const _threshold = 50.0;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _dragExtent = 0;
        _ctrl.value = 0;
      }
    });
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset =
        _ctrl.isAnimating ? _dragExtent * (1 - _ctrl.value) : _dragExtent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        setState(() {
          _dragExtent = (_dragExtent + d.delta.dx).clamp(0.0, _threshold * 1.4);
        });
      },
      onHorizontalDragEnd: (_) {
        if (_dragExtent >= _threshold) widget.onReply();
        _ctrl.forward(from: 0);
      },
      child: Stack(clipBehavior: Clip.none, children: [
        Transform.translate(offset: Offset(offset, 0), child: widget.child),
        if (offset > 5)
          Positioned(
              left: offset - 28,
              top: 0,
              bottom: 0,
              child: Center(
                  child: Icon(Icons.reply_rounded,
                      color: themed(context,
                          light: Colors.grey.shade400,
                          dark: AlanyaColors.craie2),
                      size: 22))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════
// FORWARD PICKER
// ══════════════════════════════════════════════
class _ForwardPicker extends StatefulWidget {
  const _ForwardPicker({required this.conversations, required this.title});
  final List<Conversation> conversations;
  final String title;
  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  final Set<String> _selected = {};
  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(widget.title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: Text(_selected.isEmpty ? '' : '${_selected.length}',
                    style: TextStyle(
                        color: _selected.isEmpty
                            ? themed(context,
                                light: Colors.grey, dark: AlanyaColors.craie2)
                            : themed(context,
                                light: AlanyaColors.terracotta,
                                dark: AlanyaColors.terracottaNuit),
                        fontWeight: FontWeight.bold))),
          ])),
      const Divider(height: 1),
      SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.conversations.length,
              itemBuilder: (_, i) {
                final conv = widget.conversations[i];
                final isSelected = _selected.contains(conv.id);
                return ListTile(
                  leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? themed(context,
                              light: AlanyaColors.terracotta,
                              dark: AlanyaColors.terracottaNuit)
                          : themed(context,
                              light: AlanyaColors.sand,
                              dark: surfacesOf(context).surfaceHaute),
                      child: Icon(
                          isSelected
                              ? Icons.check
                              : (conv.isGroup ? Icons.group : Icons.person),
                          color: isSelected
                              ? Colors.white
                              : themed(context,
                                  light: AlanyaColors.chocolate,
                                  dark: AlanyaColors.craie2))),
                  title: Text(conv.title ?? 'Conversation'),
                  subtitle: conv.isGroup ? const Text('Groupe') : null,
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selected.remove(conv.id);
                      } else {
                        _selected.add(conv.id);
                      }
                    });
                  },
                );
              })),
      if (_selected.isNotEmpty)
        Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AlanyaColors.terracotta,
                        foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.send),
                    label: Text(tr(context, 'send'))))),
    ]));
  }
}

/// Overlay affiché lors de l'appui long sur un message : barrière transparente
/// (tap = fermer) + bulle de réactions flottante et animée, positionnée
/// au-dessus (ou au-dessous si le message est trop haut) du message ancré.
class _ReactionBarrier extends StatefulWidget {
  const _ReactionBarrier({
    required this.anchor,
    required this.mine,
    required this.emojis,
    required this.myEmoji,
    required this.onSelect,
    required this.onDismiss,
  });

  final Rect anchor;
  final bool mine;
  final List<String> emojis;
  final String? myEmoji;
  final void Function(String) onSelect;
  final VoidCallback onDismiss;

  @override
  State<_ReactionBarrier> createState() => _ReactionBarrierState();
}

class _ReactionBarrierState extends State<_ReactionBarrier>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    const pillHeight = 56.0;
    // Place la bulle au-dessus du message ; si pas de place (message trop haut),
    // on la place au-dessous.
    final minTop = media.padding.top + kToolbarHeight + 8;
    final wantTop = widget.anchor.top - pillHeight - 8;
    final showAbove = wantTop >= minTop;
    final top = showAbove ? wantTop : widget.anchor.bottom + 8;

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        // Barrière de fermeture (tap en dehors) — commence SOUS l'AppBar
        // contextuelle pour ne pas bloquer ses boutons (Répondre, etc.).
        Positioned(
          top: media.padding.top + kToolbarHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Align(
            alignment:
                widget.mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
              alignment:
                  widget.mine ? Alignment.centerRight : Alignment.centerLeft,
              child: FadeTransition(
                opacity: _c,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: dark ? surfacesOf(context).surface : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.emojis.map((e) {
                        final selected = e == widget.myEmoji;
                        return InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => widget.onSelect(e),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? themed(context,
                                          light: AlanyaColors.terracotta,
                                          dark: AlanyaColors.terracottaNuit)
                                      .withValues(alpha: 0.18)
                                  : Colors.transparent,
                            ),
                            child:
                                Text(e, style: const TextStyle(fontSize: 24)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
