// chat_screen.dart — WhatsApp previews COMPLET (thumbnails vidéo, PDF, waveform, grille)
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../core/message_cache.dart';
import '../../../core/outbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/audio_player.dart';
import '../../../core/downloader.dart';
import '../../../core/presence_store.dart';
import '../../../core/realtime_client.dart';
import '../../../core/ringtone_service.dart';
import '../../../core/token_storage.dart';
import '../../../core/voice_recorder.dart';
import '../../../core/locale_controller.dart';
import '../../../core/translate_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/message.dart';
import '../../../models/conversation.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/auth_network_image.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../account/screens/avatar_viewer_screen.dart';
import '../../auth/auth_controller.dart';
import '../../calls/call_controller.dart';
import '../../calls/screens/active_call_screen.dart';
import '../../contacts/screens/contact_info_screen.dart';
import '../../group/screens/group_info_screen.dart';
import '../../media/media_repository.dart';
import '../chat_repository.dart';
import '../widgets/activity_indicator.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'video_viewer_screen.dart';

// ── Imports previews WhatsApp ──
import '../../../widgets/media/image_bubble.dart';
import '../../../widgets/media/video_bubble.dart';
import '../../../widgets/media/document_bubble.dart';
import '../../../widgets/media/audio_bubble.dart';
import '../../../widgets/media/link_bubble.dart';
import '../../../widgets/media/reply_media_preview.dart';
import '../../../widgets/media/media_grid.dart';
import '../../../core/media_helper.dart';
import '../chat_media_integration.dart';
import 'media_gallery_viewer.dart';
import '../../../widgets/media/media_picker_sheet.dart';
import 'gallery_screen.dart';

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
    with ChatMediaIntegrationMixin, WidgetsBindingObserver {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
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
  String? _token;
  String _baseUrl = "";
  bool _uploading = false;
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
  DateTime? _lastCueAt;
  Message? _replyTo;
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
    ChatScreen.activeConvId = widget.convId;
    _load();
    _scrollCtrl.addListener(_onScroll);
    final rt = context.read<RealtimeClient>();
    _rt = rt;
    rt.connect();
    _rtSub = rt.events.listen(_onRealtimeEvent);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    WidgetsBinding.instance.addObserver(this);
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
    } else if (_recording) {
      _emitRecording(true);
    }
  }

  @override
  void dispose() {
    ChatScreen.activeConvId = null;
    WidgetsBinding.instance.removeObserver(this);
    // Coupe les indicateurs si on quitte la conversation en pleine saisie/enreg.
    _typingDebounce?.cancel();
    _typingTimeout?.cancel();
    _recordingTimeout?.cancel();
    _emitTyping(false);
    _emitRecording(false);
    _pollTimer?.cancel();
    _recordTimer?.cancel();
    _rtSub?.cancel();
    _voiceRecorder.cancel();
    _translateService.dispose();
    InlineAudioPlayer.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
        final idx = tempId != null ? _messages.indexWhere((m) => m.id == tempId) : -1;
        if (idx >= 0) { _messages[idx] = msg; }
        else if (!_messages.any((m) => m.id == msg.id)) { _messages = [..._messages, msg]; }
      });
      if (msg.senderId != _myId) _markReadRemote();
      _scrollToBottom();
    } else if (type == "read") {
      if (e["convId"] != widget.convId) return;
      setState(() {
        _messages = _messages.map((m) => m.senderId == _myId && m.status != "READ"
            ? Message(id: m.id, convId: m.convId, senderId: m.senderId, content: m.content, type: m.type, status: "READ", replyToId: m.replyToId, replyTo: m.replyTo, deletedAt: m.deletedAt, media: m.media, createdAt: m.createdAt)
            : m).toList();
      });
    } else if (type == "message_status") {
      final messageId = e["messageId"] as String?;
      final newStatus = e["status"] as String?;
      if (messageId == null || newStatus == null) return;
      setState(() {
        _messages = _messages.map((m) => m.id == messageId && _statusRank(newStatus) > _statusRank(m.status)
            ? Message(id: m.id, convId: m.convId, senderId: m.senderId, content: m.content, type: m.type, status: newStatus, replyToId: m.replyToId, replyTo: m.replyTo, deletedAt: m.deletedAt, media: m.media, createdAt: m.createdAt)
            : m).toList();
      });
    } else if (type == "message_deleted") {
      final messageId = e["messageId"] as String?;
      final scope = e["scope"] as String? ?? "me";
      if (messageId == null || e["convId"] != widget.convId) return;
      setState(() {
        if (scope == "me") { _messages = _messages.where((m) => m.id != messageId).toList(); }
        else { _messages = _messages.map((m) => m.id == messageId
            ? Message(id: m.id, convId: m.convId, senderId: m.senderId, content: null, type: m.type, status: m.status, replyToId: m.replyToId, replyTo: m.replyTo, deletedAt: DateTime.now(), media: const [], createdAt: m.createdAt)
            : m).toList(); }
      });
    } else if (type == "typing") {
      if (e["convId"] != widget.convId) return;
      _onPeerActivity(typing: e["isTyping"] == true, uid: e["userId"] as String?);
    } else if (type == "recording") {
      if (e["convId"] != widget.convId) return;
      _onPeerActivity(recording: e["isRecording"] == true, uid: e["userId"] as String?);
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
        _typingTimeout = Timer(const Duration(seconds: 6),
            () { if (mounted) setState(() => _peerTyping = false); });
      }
      if (_peerTyping != typing) setState(() => _peerTyping = typing);
    }
    if (recording != null) {
      _recordingTimeout?.cancel();
      if (recording) {
        _recordingTimeout = Timer(const Duration(seconds: 12),
            () { if (mounted) setState(() => _peerRecording = false); });
      }
      if (_peerRecording != recording) setState(() => _peerRecording = recording);
    }
    // Bonus : son discret à l'apparition (throttlé, non répétitif).
    if (appearing && (_peerTyping || _peerRecording)) _playActivityCue();
  }

  void _playActivityCue() {
    final now = DateTime.now();
    if (_lastCueAt != null &&
        now.difference(_lastCueAt!) < const Duration(seconds: 4)) return;
    _lastCueAt = now;
    RingtoneService.instance.playCue();
  }

  void _markReadRemote() {
    final rt = context.read<RealtimeClient>();
    if (rt.connected) { rt.markRead(widget.convId); }
    else { context.read<ChatRepository>().markRead(widget.convId); }
  }

  Future<void> _load() async {
    // _myId est désormais un getter (toujours à jour) — plus besoin de le figer ici.
    _baseUrl = context.read<ApiClient>().baseUrl;
    initMediaIntegration(_baseUrl);
    _token = await context.read<TokenStorage>().accessToken;
    final cached = await MessageCache.getConv(widget.convId);
    if (cached.isNotEmpty && mounted) {
      setState(() { _messages = cached; _loading = false; });
      for (final m in _messages) { _cacheMsg(m); }
      _scrollToBottom();
    }
    try {
      final repo = context.read<ChatRepository>();
      final msgs = await repo.getMessages(widget.convId);
      if (!mounted) return;
      final reversed = msgs.reversed.toList();
      await MessageCache.putConv(widget.convId, reversed);
      setState(() { _messages = reversed; _loading = false; });
      for (final m in _messages) { _cacheMsg(m); }
      _markReadRemote();
      _scrollToBottom();
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  // Scroll infini : proche du haut → charge les messages plus anciens.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels <= 240 && !_loadingOlder && _hasMoreOlder) {
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
        setState(() => _messages = [...newMsgs, ..._messages]);
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
      final atBottom = !_scrollCtrl.hasClients || _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 60;
      setState(() => _messages = latest);
      for (final m in latest) { _cacheMsg(m); }
      if (hadMore) repo.markRead(widget.convId);
      if (hadMore && atBottom) _scrollToBottom();
    } catch (_) {}
  }

  String _signature(List<Message> msgs) => msgs.map((m) => "${m.id}:${m.status}").join("|");

  // ══════════════════════════════════════════════
  // SEND
  // ══════════════════════════════════════════════
  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _typingDebounce?.cancel();
    _emitTyping(false); // on arrête l'indicateur dès l'envoi
    final rt = context.read<RealtimeClient>();
    final replyId = _replyTo?.id;
    if (rt.connected) {
      final tempId = "tmp-${DateTime.now().microsecondsSinceEpoch}";
      final replyMsg = _replyTo;
      final replySnapshot = replyMsg != null ? ReplyPreview(id: replyMsg.id, senderId: replyMsg.senderId, type: replyMsg.type, content: replyMsg.isDeleted ? null : replyMsg.content, isDeleted: replyMsg.isDeleted) : null;
      final optimistic = Message(id: tempId, convId: widget.convId, senderId: _myId ?? "", content: text, type: "TEXT", status: "SENT", replyToId: replyId, replyTo: replySnapshot, media: const [], createdAt: DateTime.now());
      setState(() { _messages = [..._messages, optimistic]; _replyTo = null; });
      _inputCtrl.clear();
      rt.sendMessage(widget.convId, text, tempId, replyToId: replyId);
      _scrollToBottom();
      return;
    }
    setState(() { _sending = true; });
    try {
      final msg = await context.read<ChatRepository>().sendText(widget.convId, text, replyToId: replyId);
      _cacheMsg(msg);
      _inputCtrl.clear();
      setState(() { _messages = [..._messages, msg]; _replyTo = null; });
      _scrollToBottom();
    } on ApiException catch (e) { _showError(e.message); } catch (_) {
      final tempId = "out-${DateTime.now().microsecondsSinceEpoch}";
      final optimistic = Message(id: tempId, convId: widget.convId, senderId: _myId ?? "", content: text, type: "TEXT", status: "PENDING", replyToId: replyId, replyTo: null, media: const [], createdAt: DateTime.now());
      _cacheMsg(optimistic);
      _inputCtrl.clear();
      setState(() { _messages = [..._messages, optimistic]; _replyTo = null; });
      _scrollToBottom();
      await context.read<Outbox>().enqueue(tempId: tempId, convId: widget.convId, content: text, replyToId: replyId);
    } finally { if (mounted) setState(() => _sending = false); }
  }

  void _setReplyTo(Message m) { setState(() => _replyTo = m); FocusScope.of(context).requestFocus(FocusNode()); }

  // ══════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════
  Widget _statusTicks(String status, Color baseColor) {
    if (status == "PENDING") return Icon(Icons.access_time, size: 13, color: baseColor);
    if (status == "READ") return const Icon(Icons.done_all, size: 15, color: AlanyaColors.tickRead);
    if (status == "DELIVERED") return Icon(Icons.done_all, size: 15, color: baseColor);
    return Icon(Icons.done, size: 15, color: baseColor);
  }

  int _statusRank(String s) { switch (s) { case "READ": return 2; case "DELIVERED": return 1; default: return 0; } }

  Widget _timestampRow(Message m, bool mine, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(_time(m.createdAt), style: TextStyle(fontSize: 10, color: color)),
      if (mine) ...[const SizedBox(width: 4), _statusTicks(m.status, color)],
    ]);
  }

  Message? _findMessage(String? id) {
    if (id == null) return null;
    try { return _messages.firstWhere((m) => m.id == id); } catch (_) { return null; }
  }

  void _cacheMsg(Message m) {
    _replySnapshots[m.id] = ReplyPreview(id: m.id, senderId: m.senderId, type: m.type, content: m.isDeleted ? null : m.content, isDeleted: m.isDeleted);
  }

  ReplyPreview? _resolveReply(Message m) {
    if (m.replyTo != null) return m.replyTo;
    if (m.replyToId == null) return null;
    final cached = _replySnapshots[m.replyToId];
    if (cached != null) return cached;
    final live = _findMessage(m.replyToId);
    if (live != null) { _cacheMsg(live); return _replySnapshots[live.id]; }
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
          final older = await context.read<ChatRepository>().getMessages(widget.convId, cursor: cursor);
          if (older.isEmpty) break;
          final newMsgs = older.reversed.toList();
          setState(() => _messages = [...newMsgs, ..._messages]);
          for (final m in newMsgs) { _cacheMsg(m); }
          foundIdx = _messages.indexWhere((m) => m.id == id);
          if (foundIdx >= 0) break;
        } catch (_) { break; }
      }
    }
    if (foundIdx < 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Message introuvable"), duration: Duration(seconds: 2)));
      return;
    }
    if (!_scrollCtrl.hasClients) return;
    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    final ratio = foundIdx / _messages.length;
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
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, alignment: 0.3);
      _highlightMessage(id);
    } else {
      _scrollCtrl.animateTo(estimatedOffset, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      _highlightMessage(id);
    }
  }

  void _highlightMessage(String id) {
    setState(() => _highlightedMessageId = id);
    Future.delayed(const Duration(seconds: 2), () { if (mounted && _highlightedMessageId == id) setState(() => _highlightedMessageId = null); });
  }

  String _replyPreviewText(Message? original, ReplyPreview? snapshot) {
    if (snapshot != null) {
      if (snapshot.isDeleted) return tr(context, 'message_deleted');
      if (snapshot.content != null) return snapshot.content!;
      return _typeLabel(snapshot.type);
    }
    if (original == null) return '...';
    if (original.isDeleted) return tr(context, 'message_deleted');
    if (original.content != null) return original.content!;
    if (original.media.isNotEmpty) return original.media.first.filename ?? 'Fichier';
    return _typeLabel(original.type);
  }

  String _typeLabel(String type) {
    switch (type) { case 'IMAGE': return 'Photo'; case 'AUDIO': return 'Message vocal'; case 'VIDEO': return 'Vidéo'; case 'FILE': return 'Fichier'; default: return '[$type]'; }
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
    final hasMedia = original != null && original.media.isNotEmpty && !original.isDeleted;
    return GestureDetector(
      onTap: original != null ? () => _scrollToMessage(m.replyToId!) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: hasMedia
            ? ReplyMediaPreview(
                replyToContent: original.content,
                replyToMediaUrl: '$_baseUrl${original.media.first.url}?token=$_token',
                replyToMimeType: original.media.first.mimeType,
                replyToFileName: original.media.first.filename,
                replyToSenderName: senderName,
                isMe: mine,
              )
            : _replyPreviewTextOnly(m, mine, snapshot, original, senderName),
      ),
    );
  }

  Widget _replyPreviewTextOnly(Message m, bool mine, dynamic snapshot, Message? original, String senderName) {
    final onColor = mine ? Colors.white : AlanyaColors.ink;
    final barColor = mine ? Colors.white70 : AlanyaColors.terracotta;
    final previewText = _replyPreviewText(original, snapshot);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: mine ? Colors.white.withOpacity(0.15) : AlanyaColors.sand.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: barColor, width: 3)),
      ),
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(senderName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: barColor)),
        const SizedBox(height: 2),
        Text(previewText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: onColor.withOpacity(0.8))),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // FILE PICKER + UPLOAD
  // ══════════════════════════════════════════════
    Future<void> _pickAndSendFile() async {
    final result = await MediaPickerSheet.show(context);
    if (result == null) return;

    // Contact sélectionné → envoie le numéro comme message texte
    if (result is ContactPickResult) {
      final numbers = result.publicNumbers.join(', ');
      _inputCtrl.text = numbers;
      _send();
      return;
    }

    // Médias sélectionnés
    final files = result as List<MediaPickResult>;
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    final replyId = _replyTo?.id;
    final replyMsg = _replyTo;
    final replySnapshot = replyMsg != null
        ? ReplyPreview(id: replyMsg.id, senderId: replyMsg.senderId, type: replyMsg.type, content: replyMsg.isDeleted ? null : replyMsg.content, isDeleted: replyMsg.isDeleted)
        : null;
    if (mounted) setState(() => _replyTo = null);
    final mediaRepo = context.read<MediaRepository>();
    final rt = context.read<RealtimeClient>();
    try {
      final uploadedIds = <String>[];
      String? firstMime;
      for (final f in files) {
        final uploaded = await mediaRepo.upload(Uint8List.fromList(f.bytes), f.fileName, f.mimeType, durationMs: f.durationMs);
        uploadedIds.add(uploaded.id);
        firstMime ??= f.mimeType;
      }
      final msgType = firstMime!.startsWith('image/') ? 'IMAGE' : firstMime.startsWith('video/') ? 'VIDEO' : firstMime.startsWith('audio/') ? 'AUDIO' : 'FILE';
      if (rt.connected) {
        rt.sendMultiMedia(widget.convId, uploadedIds, msgType, "tmp-${DateTime.now().microsecondsSinceEpoch}", replyToId: replyId);
      } else {
        final repo = context.read<ChatRepository>();
        final msg = await repo.sendMultiMedia(widget.convId, uploadedIds, msgType, replyToId: replyId);
        if (mounted) setState(() => _messages = [..._messages, msg]);
      }
      _scrollToBottom();
    } on ApiException catch (e) { _showError(e.message); } catch (_) { _showError(tr(context, 'send_failed')); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  Future<void> _uploadAndSend(List<int> bytes, String filename, String mime, String msgType, {int? durationMs}) async {
    setState(() => _uploading = true);
    final replyId = _replyTo?.id;
    final replyMsg = _replyTo;
    final replySnapshot = replyMsg != null ? ReplyPreview(id: replyMsg.id, senderId: replyMsg.senderId, type: replyMsg.type, content: replyMsg.isDeleted ? null : replyMsg.content, isDeleted: replyMsg.isDeleted) : null;
    if (mounted) setState(() => _replyTo = null);
    final media = context.read<MediaRepository>();
    final rt = context.read<RealtimeClient>();
    try {
      final uploaded = await media.upload(Uint8List.fromList(bytes), filename, mime, durationMs: durationMs);
      if (rt.connected) { rt.sendMedia(widget.convId, uploaded.id, msgType, "tmp-${DateTime.now().microsecondsSinceEpoch}", replyToId: replyId); }
      else { final msg = await context.read<ChatRepository>().sendMedia(widget.convId, uploaded.id, msgType, replyToId: replyId); if (mounted) setState(() => _messages = [..._messages, msg]); }
      _scrollToBottom();
    } on ApiException catch (e) { _showError(e.message); } catch (_) { _showError(tr(context, 'send_failed')); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  // ══════════════════════════════════════════════
  // VOICE RECORDING
  // ══════════════════════════════════════════════
  void _startRecordTimer() {
    _recordTimer?.cancel();
    _recordDuration = Duration.zero;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (!mounted) return; setState(() { _recordDuration = DateTime.now().difference(_recordStarted ?? DateTime.now()); }); });
  }
  void _stopRecordTimer() { _recordTimer?.cancel(); _recordTimer = null; }
  String _formatDuration(Duration d) { final m = d.inMinutes.remainder(60); final s = d.inSeconds.remainder(60); return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'; }

  Future<void> _startVoiceRecord() async {
    if (_uploading || _recording || _voiceActive) return;
    _voiceActive = true;
    if (!_voiceRecorder.isSupported) { _voiceActive = false; _showError(tr(context, 'micro_unavailable_platform')); return; }
    final ok = await _voiceRecorder.start();
    if (!ok || !_voiceActive) { if (ok) _voiceRecorder.cancel(); _voiceActive = false; if (ok) _showError(tr(context, 'micro_unavailable')); return; }
    if (!mounted) return;
    setState(() { _recording = true; _recordLocked = false; _recordStarted = DateTime.now(); });
    _startRecordTimer();
    _typingDebounce?.cancel();
    _emitTyping(false); // pas de "écrit" pendant un vocal
    _emitRecording(true);
  }

  Future<void> _stopVoiceRecord({bool cancel = false}) async {
    _voiceActive = false;
    if (!_recording) return;
    _stopRecordTimer();
    setState(() { _recording = false; _recordLocked = false; _recordDuration = Duration.zero; });
    _emitRecording(false);
    if (cancel) { _voiceRecorder.cancel(); return; }
    final result = await _voiceRecorder.stop();
    if (result == null || result.bytes.isEmpty) return;
    final ext = kIsWeb ? "webm" : "m4a";
    final mime = kIsWeb ? "audio/webm" : "audio/mp4";
    await _uploadAndSend(result.bytes, "vocal-${DateTime.now().millisecondsSinceEpoch}.$ext", mime, "AUDIO", durationMs: result.durationMs);
  }

  String _ext(String name) { final i = name.lastIndexOf("."); return i >= 0 ? name.substring(i + 1).toLowerCase() : ""; }
  String _mimeFromName(String name) {
    switch (_ext(name)) {
      case "png": return "image/png"; case "gif": return "image/gif"; case "webp": return "image/webp";
      case "jpg": case "jpeg": return "image/jpeg"; case "pdf": return "application/pdf";
      case "doc": return "application/msword"; case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
      case "xls": return "application/vnd.ms-excel"; case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
      case "ppt": case "pptx": return "application/vnd.ms-powerpoint"; case "txt": return "text/plain";
      case "csv": return "text/csv"; case "zip": return "application/zip"; case "rar": return "application/vnd.rar";
      case "7z": return "application/x-7z-compressed"; case "mp3": return "audio/mpeg"; case "wav": return "audio/wav";
      case "mp4": return "video/mp4"; case "mov": return "video/quicktime"; default: return "application/octet-stream";
    }
  }

  Future<String> _freshToken() async { _token = await context.read<TokenStorage>().accessToken; return _token ?? ''; }
  String _mediaUrl(MessageMedia m) => "$_baseUrl${m.url}?token=${_token ?? ''}";
  String _downloadUrl(MessageMedia m) => "$_baseUrl${m.url}?download=1&token=${_token ?? ''}";

  Future<void> _download(MessageMedia m) async {
    final token = await _freshToken();
    final url = "$_baseUrl${m.url}?download=1&token=$token";
    final name = m.filename ?? "fichier-${m.id}";
    final path = await downloadUrl(url, name);
    if (!mounted) return;
    if (path != null) { showAppSnackBar("Enregistré dans Alanya/ : $name"); } else { showAppSnackBar("Échec du téléchargement"); }
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfUrl: "$_baseUrl${media.url}?token=$token", downloadUrl: "$_baseUrl${media.url}?download=1&token=$token", filename: media.filename ?? "document-${media.id}.pdf")));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); });
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
      if (rt.connected) { rt.deleteMessage(m.id, scope: scope); } else { await context.read<ChatRepository>().deleteMessage(widget.convId, m.id, scope: scope); }
      if (!mounted) return;
      setState(() {
        if (scope == "me") { _messages = _messages.where((msg) => msg.id != m.id).toList(); }
        else { _messages = _messages.map((msg) => msg.id == m.id ? Message(id: m.id, convId: m.convId, senderId: m.senderId, content: null, type: m.type, status: m.status, replyToId: m.replyToId, replyTo: m.replyTo, deletedAt: DateTime.now(), media: const [], createdAt: m.createdAt) : msg).toList(); }
      });
    } on ApiException catch (e) { _showError(e.message); } catch (_) { _showError(tr(context, 'send_failed')); }
  }

  Future<String?> _showDeleteDialog(bool canDeleteForAll) {
    return showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.delete_outline, color: AlanyaColors.chocolate), title: Text(tr(context, 'delete_for_me')), onTap: () => Navigator.pop(ctx, "me")),
      if (canDeleteForAll) ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: Text(tr(context, 'delete_for_everyone')), onTap: () => Navigator.pop(ctx, "everyone")),
    ])));
  }

  Future<void> _forwardMessage(Message m) async {
    final conversations = await context.read<ChatRepository>().listConversations();
    if (!mounted) return;
    final picked = <String>{};
    await showModalBottomSheet<Set<String>>(context: context, isScrollControlled: true, builder: (ctx) => _ForwardPicker(conversations: conversations.where((c) => c.id != widget.convId).toList(), title: tr(context, 'forward_to'))).then((result) { if (result != null) picked.addAll(result); });
    if (picked.isEmpty || !mounted) return;
    final rt = context.read<RealtimeClient>();
    try {
      if (rt.connected) { rt.forwardMessage(m.id, picked.toList()); } else { await context.read<ChatRepository>().forwardMessage(widget.convId, m.id, picked.toList()); }
      if (mounted) showAppSnackBar(tr(context, 'forwarded_success'));
    } on ApiException catch (e) { _showError(e.message); } catch (_) { _showError(tr(context, 'send_failed')); }
  }

  void _showMessageOptions(Message m) {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (!m.isDeleted) ...[
        ListTile(leading: const Icon(Icons.reply, color: AlanyaColors.terracotta), title: Text(tr(context, 'reply')), onTap: () { Navigator.pop(ctx); _setReplyTo(m); }),
        ListTile(leading: const Icon(Icons.forward, color: AlanyaColors.forest), title: Text(tr(context, 'forward')), onTap: () { Navigator.pop(ctx); _forwardMessage(m); }),
        ListTile(leading: const Icon(Icons.copy, color: AlanyaColors.chocolate), title: Text(tr(context, 'copy')), onTap: () { Navigator.pop(ctx); if (m.content != null) { Clipboard.setData(ClipboardData(text: m.content!)); showAppSnackBar(tr(context, 'copied')); } }),
      ],
      ListTile(leading: Icon(m.isDeleted ? Icons.delete_outline : Icons.delete, color: Colors.red), title: Text(tr(context, 'delete')), onTap: () { Navigator.pop(ctx); _deleteMessage(m); }),
    ])));
  }

  Future<void> _startCall(String type) async {
    final cc = context.read<CallController>();
    try {
      await cc.startOutgoing(widget.convId, type, widget.title);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ActiveCallScreen()));
    } on StateError catch (_) { _showError("Tu es déjà en appel"); } catch (e) {
      final msg = e.toString();
      if (msg.contains("PERMISSION_DENIED")) { _showError("Micro/caméra requis. Accorde les permissions dans les réglages."); }
      else if (msg.contains("409") || msg.contains("BUSY")) { _showError("Impossible de démarrer l'appel. Réessaie dans un instant."); }
      else { _showError("Erreur d'appel : vérifie ta connexion et réessaie."); }
    }
  }

  // ══════════════════════════════════════════════
  // APPBAR
  // ══════════════════════════════════════════════
  PreferredSizeWidget _whatsappAppBar() {
    return AppBar(
      backgroundColor: AlanyaColors.terracotta, foregroundColor: Colors.white, leadingWidth: 40, titleSpacing: 0,
      title: InkWell(
        onTap: widget.isGroup ? _openGroupInfo : _openContactInfo,
        child: Row(children: [
          GestureDetector(onTap: _openAvatarViewer, child: AvatarCircle(name: widget.title, avatarUrl: widget.avatarUrl, radius: 18, backgroundColor: Colors.white24)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (widget.isGroup)
              Text("${widget.memberNames.length} membres", style: const TextStyle(fontSize: 11, color: Colors.white70))
            else
              // Présence LIVE : lit le PresenceStore (mis à jour par les events WS
              // `presence`), avec repli sur les données REST passées au widget.
              Consumer<PresenceStore>(builder: (ctx, presence, _) {
                final uid = widget.otherUserId;
                final online = (uid != null ? presence.isOnline(uid) : null) ?? (widget.otherIsOnline == 1);
                final ls = (uid != null ? presence.lastSeen(uid) : null) ?? widget.otherLastSeen;
                String? sub;
                if (online) {
                  sub = "en ligne";
                } else if (ls != null) {
                  sub = _lastSeenLabel(ls);
                } else if (widget.otherStatusMsg?.isNotEmpty == true) {
                  sub = widget.otherStatusMsg;
                }
                if (sub == null) return const SizedBox.shrink();
                return Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70));
              }),
          ])),
        ]),
      ),
      actions: [
        if (!widget.isGroup) ...[
          IconButton(tooltip: "Appel vidéo", icon: const Icon(Icons.videocam), onPressed: () => _startCall("VIDEO")),
          IconButton(tooltip: "Appel audio", icon: const Icon(Icons.call), onPressed: () => _startCall("AUDIO")),
        ],
      ],
    );
  }

  void _openAvatarViewer() { Navigator.of(context).push(MaterialPageRoute(builder: (_) => AvatarViewerScreen(name: widget.title, avatarUrl: widget.avatarUrl))); }
  void _openGroupInfo() {
    if (!widget.isGroup) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupInfoScreen(convId: widget.convId, title: widget.title, avatarUrl: widget.avatarUrl, members: widget.memberNames.entries.map((e) => {'id': e.key, 'pseudo': e.value, 'publicNumber': '', 'avatarUrl': null, 'isOnline': 0, 'role': 'MEMBER'}).toList())));
  }
  void _openContactInfo() {
    if (widget.isGroup) return;
    final otherId = widget.otherUserId;
    if (otherId == null) { _openAvatarViewer(); return; }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContactInfoScreen(userId: otherId, name: widget.title, publicNumber: widget.otherPublicNumber ?? "", avatarUrl: widget.avatarUrl, statusMsg: widget.otherStatusMsg, convId: widget.convId, contactId: widget.contactId, isBlocked: widget.isBlocked, isOnline: widget.otherIsOnline == 1, lastSeen: widget.otherLastSeen)));
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
      appBar: _whatsappAppBar(),
      body: MotifBackground(
        overlayOpacity: 0.85,
        child: Column(children: [
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(color: AlanyaColors.terracotta))
              : _messages.isEmpty
                  ? Center(child: Text(tr(context, 'no_messages')))
                  : ListView.builder(controller: _scrollCtrl, padding: const EdgeInsets.all(12), itemCount: _messages.length, itemBuilder: (_, i) {
                    final widgets = <Widget>[];
                    if (_needsDateSeparator(i)) widgets.add(_dateChip(_dateLabel(_messages[i].createdAt)));
                    widgets.add(_bubble(_messages[i], _messages[i].senderId == myId));
                    return Column(children: widgets);
                  })),
          if (!widget.isGroup)
            ActivityIndicatorBar(typing: _peerTyping, recording: _peerRecording),
          _composer(),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // BUBBLE — WhatsApp previews + grille multi-médias
  // ══════════════════════════════════════════════
  Widget _bubble(Message m, bool mine) {
    final hasMedia = m.media.isNotEmpty;
    final isMultiMedia = hasMedia && m.media.length > 1;
    final isImage = !isMultiMedia && m.type == "IMAGE" && hasMedia;
    final isVideo = !isMultiMedia && m.type == "VIDEO" && hasMedia;
    final isFile = !isMultiMedia && m.type == "FILE" && hasMedia;
    final isAudio = !isMultiMedia && m.type == "AUDIO" && hasMedia;
    final senderLabel = widget.isGroup && !mine ? (widget.memberNames[m.senderId] ?? "Membre") : null;
    final isHighlighted = _highlightedMessageId == m.id;
    final isGrid = isMultiMedia; // 2+ médias → grille

    return Align(
      key: _messageKeys.putIfAbsent(m.id, () => GlobalKey()),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (senderLabel != null) Padding(padding: const EdgeInsets.only(left: 4, bottom: 2), child: Text(senderLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AlanyaColors.forest))),
        _SwipeToReply(
          onReply: () => _setReplyTo(m),
          child: GestureDetector(
            onLongPress: () => _showMessageOptions(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: (isImage || isVideo || isGrid) ? const EdgeInsets.all(3) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(
                color: isHighlighted ? AlanyaColors.gold.withValues(alpha: 0.3) : (mine ? AlanyaColors.terracotta : Colors.white),
                borderRadius: BorderRadius.circular(14),
                border: mine ? null : Border.all(color: isHighlighted ? AlanyaColors.gold : AlanyaColors.sand),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (m.replyToId != null && !m.isDeleted) _replyPreviewHeader(m, mine),
                m.isDeleted
                    ? _deletedBubble(m, mine)
                    : isGrid
                        ? MediaGrid(
                            items: m.media.map((media) => MediaGridItem(
                              url: media.url, mimeType: media.mimeType, fileName: media.filename,
                              sizeBytes: media.sizeBytes, durationMs: media.durationMs,
                            )).toList(),
                            baseUrl: _baseUrl, token: _token,
                            onItemTap: (i) {
                              // Ouvre la visionneuse navigable (swipe) sur tous
                              // les médias de la conversation, au média touché.
                              if (i >= 0 && i < m.media.length) {
                                _openGallery(m.media[i].id);
                              }
                            },
                            onMoreTap: () {
                              // Ouvre la galerie au début pour les "+N"
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => GalleryScreen(
                                  items: m.media.map((media) => GalleryItem(
                                    url: media.url, mimeType: media.mimeType, fileName: media.filename,
                                    sizeBytes: media.sizeBytes, durationMs: media.durationMs,
                                  )).toList(),
                                  baseUrl: _baseUrl, token: _token,
                                  initialIndex: 0,
                                ),
                              ));
                            },
                            timestamp: _time(m.createdAt),
                            statusWidget: mine ? _statusTicks(m.status, Colors.white) : null,
                            isMe: mine,
                          )
                        : isImage
                            ? ImageBubble(
                                imageUrl: '$_baseUrl${m.media.first.url}', token: _token,
                                onTap: () => _openImageViewer(m), onLongPress: () => _showMessageOptions(m),
                                timestamp: _time(m.createdAt),
                                statusWidget: mine ? _statusTicks(m.status, Colors.white) : null,
                                isMe: mine,
                              )
                            : isVideo
                                ? VideoBubble(
                                    videoUrl: '$_baseUrl${m.media.first.url}', token: _token,
                                    duration: m.media.first.durationMs,
                                    onTap: () => _openVideoViewer(m), onLongPress: () => _showMessageOptions(m),
                                    timestamp: _time(m.createdAt),
                                    statusWidget: mine ? _statusTicks(m.status, Colors.white) : null,
                                    isMe: mine,
                                  )
                                : isFile
                                    ? DocumentBubble(
                                        fileName: m.media.first.filename ?? tr(context, 'file'),
                                        fileSize: m.media.first.sizeBytes,
                                        mimeType: m.media.first.mimeType,
                                        pdfUrl: '$_baseUrl${m.media.first.url}',
                                        token: _token,
                                        onTap: () {
                                          final media = m.media.first;
                                          final isPdf = media.mimeType == "application/pdf" || _ext(media.filename ?? "").toLowerCase() == "pdf";
                                          isPdf ? _openPdfViewer(m) : _openDocument(media);
                                        },
                                        onLongPress: () => _showMessageOptions(m),
                                        timestamp: _time(m.createdAt),
                                        statusWidget: mine ? _statusTicks(m.status, mine ? Colors.white70 : Colors.black45) : null,
                                        isMe: mine,
                                      )
                                    : isAudio
                                        ? AudioBubble(
                                            url: _mediaUrl(m.media.first),
                                            duration: m.media.first.durationMs,
                                            onTap: () => InlineAudioPlayer.toggle(_mediaUrl(m.media.first), totalDuration: m.media.first.durationMs != null ? Duration(milliseconds: m.media.first.durationMs!) : null),
                                            timestamp: _time(m.createdAt),
                                            statusWidget: mine ? _statusTicks(m.status, mine ? Colors.white70 : Colors.black45) : null,
                                            isMe: mine,
                                          )
                                        : _textBubble(m, mine),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _deletedBubble(Message m, bool mine) {
    final onSub = mine ? Colors.white70 : Colors.black45;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 14, color: onSub),
        const SizedBox(width: 6),
        Text(tr(context, 'message_deleted'), style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: onSub)),
      ]),
      const SizedBox(height: 2),
      Text(_time(m.createdAt), style: TextStyle(fontSize: 10, color: onSub)),
    ]);
  }

  // ══ TEXT BUBBLE AVEC LINK PREVIEW ══
  Widget _textBubble(Message m, bool mine) {
    final translated = _translations[m.id];
    final isTranslating = _translating.contains(m.id);
    final onTextColor = mine ? Colors.white : AlanyaColors.ink;
    final onSubColor = mine ? Colors.white70 : Colors.black45;
    return GestureDetector(
      onTap: m.type == 'TEXT' && (m.content ?? '').isNotEmpty ? () => _translateMessage(m) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.content ?? "[${m.type}]", style: TextStyle(color: onTextColor)),
        if ((m.content ?? '').isNotEmpty) buildLinkPreview(m.content!, mine),
        if (translated != null) ...[
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: mine ? Colors.white.withOpacity(0.15) : AlanyaColors.sand.withOpacity(0.7), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.translate, size: 12, color: onSubColor), const SizedBox(width: 4), Text(tr(context, 'translated'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: onSubColor))]),
            const SizedBox(height: 2),
            Text(translated, style: TextStyle(fontSize: 13, color: onTextColor, fontStyle: FontStyle.italic)),
          ])),
        ],
        if (isTranslating) ...[
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: onSubColor)), const SizedBox(width: 6), Text(tr(context, 'translating'), style: TextStyle(fontSize: 10, color: onSubColor))]),
        ],
        if (!isTranslating && translated == null && m.type == 'TEXT')
          Padding(padding: const EdgeInsets.only(top: 2), child: Text(tr(context, 'translate'), style: TextStyle(fontSize: 10, color: onSubColor.withOpacity(0.8), fontStyle: FontStyle.italic))),
        const SizedBox(height: 2),
        _timestampRow(m, mine, onSubColor),
      ]),
    );
  }

  Future<void> _translateMessage(Message m) async {
    final text = (m.content ?? '').trim();
    if (text.isEmpty) return;
    final locale = context.read<LocaleController>().languageCode;
    if (_translations.containsKey(m.id)) { setState(() => _translations.remove(m.id)); return; }
    if (_translating.contains(m.id)) return;
    setState(() => _translating.add(m.id));
    try {
      final translated = await _translateService.translate(text: text, target: locale, source: 'auto');
      if (!mounted) return;
      setState(() => _translations[m.id] = translated);
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'translation_failed')))); }
    finally { if (mounted) setState(() => _translating.remove(m.id)); }
  }

  // ══ TIME / DATE ══
  String _time(DateTime d) { final l = d.toLocal(); return "${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}"; }
  String _lastSeenLabel(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "vu à l'instant";
    if (diff.inMinutes < 60) return "vu il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "vu il y a ${diff.inHours}h";
    return "vu il y a ${diff.inDays}j";
  }
  Widget _dateChip(String label) {
    return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AlanyaColors.grey600))));
  }
  String _dateLabel(DateTime d) {
    final l = d.toLocal(); final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day); final msgDay = DateTime(l.year, l.month, l.day); final diff = today.difference(msgDay).inDays;
    if (diff == 0) return "Aujourd'hui"; if (diff == 1) return "Hier";
    if (diff < 7) { const days = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche']; return days[l.weekday - 1]; }
    const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return "${l.day} ${months[l.month - 1]} ${l.year}";
  }
  bool _needsDateSeparator(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1].createdAt.toLocal(); final curr = _messages[index].createdAt.toLocal();
    return prev.year != curr.year || prev.month != curr.month || prev.day != curr.day;
  }

  // ══════════════════════════════════════════════
  // COMPOSER (inchangé)
  // ══════════════════════════════════════════════
  Widget _composer() {
    if (_recordLocked) {
      return SafeArea(top: false, child: Container(padding: const EdgeInsets.all(8), color: AlanyaColors.cream, child: Row(children: [
        GestureDetector(onTap: () => _stopVoiceRecord(cancel: true), child: CircleAvatar(backgroundColor: Colors.red.shade400, child: const Icon(Icons.delete_outline, color: Colors.white))),
        const SizedBox(width: 8),
        Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)), child: Row(children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14), const SizedBox(width: 8),
          Text(_formatDuration(_recordDuration), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade700, fontSize: 15)),
          const Spacer(), Icon(Icons.lock, color: Colors.red.shade400, size: 18), const SizedBox(width: 4),
          Text(tr(context, 'recording_locked'), style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ]))),
        const SizedBox(width: 8),
        GestureDetector(onTap: _uploading ? null : () => _stopVoiceRecord(), child: CircleAvatar(backgroundColor: AlanyaColors.terracotta, child: const Icon(Icons.send, color: Colors.white))),
      ])));
    }
    return SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_replyTo != null) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: AlanyaColors.cream, child: Row(children: [
        Container(width: 3, height: 32, decoration: BoxDecoration(color: AlanyaColors.terracotta, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_replyTo!.senderId == _myId ? tr(context, 'you') : (widget.memberNames[_replyTo!.senderId] ?? tr(context, 'reply_to')), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AlanyaColors.terracotta)),
          Text(_replyTo!.isDeleted ? tr(context, 'message_deleted') : (_replyTo!.content ?? (_replyTo!.media.isNotEmpty ? '📎 ${_replyTo!.media.first.filename ?? tr(context, 'file')}' : '...')), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ])),
        GestureDetector(onTap: () => setState(() => _replyTo = null), child: const Icon(Icons.close, size: 20, color: Colors.black54)),
      ])),
      Container(padding: const EdgeInsets.all(8), color: AlanyaColors.cream, child: Row(children: [
        Offstage(offstage: _recording, child: IconButton(tooltip: tr(context, 'attach_file'), icon: _uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.attach_file, color: AlanyaColors.chocolate), onPressed: _uploading ? null : _pickAndSendFile)),
        Expanded(child: _recording ? _recordingBar() : TextField(controller: _inputCtrl, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onChanged: _onInputChanged, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: tr(context, 'write_message'), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
        const SizedBox(width: 4),
        _micButton(),
        Offstage(offstage: _recording, child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 8), CircleAvatar(backgroundColor: AlanyaColors.terracotta, child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sending ? null : _send))])),
      ])),
    ]));
  }

  Widget _recordingBar() {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)), child: Row(children: [
      const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14), const SizedBox(width: 8),
      Text(_formatDuration(_recordDuration), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade700, fontSize: 15)),
      const SizedBox(width: 12),
      Expanded(child: Text(tr(context, 'slide_up_to_lock'), style: const TextStyle(fontSize: 13, color: Colors.black54), textAlign: TextAlign.center)),
      const Icon(Icons.keyboard_arrow_up, color: Colors.black38, size: 20),
    ]));
  }

  Widget _micButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _startVoiceRecord(),
      onLongPressMoveUpdate: (details) { if (details.offsetFromOrigin.dy < -60 && _recording && !_recordLocked) setState(() => _recordLocked = true); },
      onLongPressEnd: (_) { if (_recording && !_recordLocked) _stopVoiceRecord(); },
      onLongPressCancel: () { if (_recording && !_recordLocked) _stopVoiceRecord(cancel: true); },
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        CircleAvatar(backgroundColor: _recording ? Colors.red : AlanyaColors.chocolate, child: Icon(_recording ? Icons.mic : Icons.mic_none, color: Colors.white, size: 22)),
        if (_recording) Positioned(top: -30, child: Container(width: 28, height: 28, decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle), child: const Icon(Icons.lock_open, color: Colors.white, size: 14))),
      ]),
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
class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _dragExtent = 0;
  static const _threshold = 50.0;
  @override
  void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200)); _ctrl.addStatusListener((status) { if (status == AnimationStatus.completed) { _dragExtent = 0; _ctrl.value = 0; } }); _ctrl.addListener(() => setState(() {})); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final offset = _ctrl.isAnimating ? _dragExtent * (1 - _ctrl.value) : _dragExtent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) { setState(() { _dragExtent = (_dragExtent + d.delta.dx).clamp(0.0, _threshold * 1.4); }); },
      onHorizontalDragEnd: (_) { if (_dragExtent >= _threshold) widget.onReply(); _ctrl.forward(from: 0); },
      child: Stack(clipBehavior: Clip.none, children: [
        Transform.translate(offset: Offset(offset, 0), child: widget.child),
        if (offset > 5) Positioned(left: offset - 28, top: 0, bottom: 0, child: Center(child: Icon(Icons.reply_rounded, color: Colors.grey[400], size: 22))),
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
    return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(16), child: Row(children: [
        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(),
        TextButton(onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected), child: Text(_selected.isEmpty ? '' : '${_selected.length}', style: TextStyle(color: _selected.isEmpty ? Colors.grey : AlanyaColors.terracotta, fontWeight: FontWeight.bold))),
      ])),
      const Divider(height: 1),
      SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: ListView.builder(shrinkWrap: true, itemCount: widget.conversations.length, itemBuilder: (_, i) {
        final conv = widget.conversations[i]; final isSelected = _selected.contains(conv.id);
        return ListTile(
          leading: CircleAvatar(backgroundColor: isSelected ? AlanyaColors.terracotta : AlanyaColors.sand, child: Icon(isSelected ? Icons.check : (conv.isGroup ? Icons.group : Icons.person), color: isSelected ? Colors.white : AlanyaColors.chocolate)),
          title: Text(conv.title ?? 'Conversation'), subtitle: conv.isGroup ? const Text('Groupe') : null,
          onTap: () { setState(() { if (isSelected) { _selected.remove(conv.id); } else { _selected.add(conv.id); } }); },
        );
      })),
      if (_selected.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: AlanyaColors.terracotta, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context, _selected), icon: const Icon(Icons.send), label: Text(tr(context, 'send'))))),
    ]));
  }
}
