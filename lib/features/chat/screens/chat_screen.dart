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
import '../../../core/realtime_client.dart';
import '../../../core/token_storage.dart';
import '../../../core/voice_recorder.dart';
import '../../../core/locale_controller.dart';
import '../../../core/translate_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/message.dart';
import '../../../models/conversation.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/auth_network_image.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../account/screens/avatar_viewer_screen.dart';
import '../../auth/auth_controller.dart';
import '../../calls/call_controller.dart';
import '../../calls/screens/active_call_screen.dart';
import '../../contacts/screens/contact_info_screen.dart';
import '../../media/media_repository.dart';
import '../chat_repository.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'video_viewer_screen.dart';

class ChatScreen extends StatefulWidget {
  /// ID de la conversation actuellement ouverte (null si aucune).
  /// Utilisé pour éviter les notifications locales quand on lit déjà la conv.
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
  });
  final String convId;
  final String title;
  final bool isGroup;
  final Map<String, String> memberNames;
  // Champs additionnels pour l'AppBar façon WhatsApp :
  final String? avatarUrl;      // avatar du peer (DM) ou du groupe
  final String? otherUserId;    // id du peer (DM uniquement)
  final String? otherPublicNumber;
  final String? otherStatusMsg;
  final String? contactId;      // pour ContactInfoScreen (bloquer/débloquer)
  final bool isBlocked;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
  String? _myId;
  String? _token;
  String _baseUrl = "";
  bool _uploading = false;
  final _voiceRecorder = VoiceRecorder();
  bool _recording = false;
  DateTime? _recordStarted;
  bool _recordLocked = false; // vrai quand l'utilisateur a verrouillé (slide up)
  Duration _recordDuration = Duration.zero; // minuteur en direct
  Timer? _recordTimer;
  bool _voiceActive = false; // garde-fou anti-race : true pendant l'appui ET l'enregistrement

  // --- Réponse à un message (swipe-to-reply) ---
  Message? _replyTo;
  // Clés globales pour chaque message → permet le scroll-to-message au clic sur une réponse.
  final Map<String, GlobalKey> _messageKeys = {};
  // Cache local des snapshots de messages cités (replyTo).
  // Indépendant de _messages : survit aux réconciliations/rebuilds.
  // Clé = messageId, Valeur = snapshot ReplyPreview.
  final Map<String, ReplyPreview> _replySnapshots = {};

  // --- Traduction ---
  final _translateService = TranslateService();
  final Map<String, String> _translations = {};
  final Set<String> _translating = {};

  @override
  void initState() {
    super.initState();
    ChatScreen.activeConvId = widget.convId; // marque cette conv comme "active"
    _load();
    final rt = context.read<RealtimeClient>();
    rt.connect(); // au cas où la connexion ne serait pas encore ouverte
    _rtSub = rt.events.listen(_onRealtimeEvent);
    // Polling de repli : actif uniquement quand le WebSocket n'est pas connecté.
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    ChatScreen.activeConvId = null; // plus aucune conv active
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

  /// Traite un événement temps réel concernant cette conversation.
  void _onRealtimeEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final type = e["type"];
    if (type == "message") {
      final data = e["message"] as Map<String, dynamic>?;
      if (data == null || data["convId"] != widget.convId) return;
      final msg = Message.fromJson(data);
      _cacheMsg(msg); // cache le snapshot dès la réception
      final tempId = e["tempId"] as String?;
      setState(() {
        // Réconcilie l'optimiste (par tempId) sinon ajoute si nouveau.
        final idx = tempId != null ? _messages.indexWhere((m) => m.id == tempId) : -1;
        if (idx >= 0) {
          _messages[idx] = msg;
        } else if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
      });
      // Message entrant => marquer lu.
      if (msg.senderId != _myId) _markReadRemote();
      _scrollToBottom();
    } else if (type == "read") {
      if (e["convId"] != widget.convId) return;
      // L'autre a lu : passe mes messages à READ.
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
                    media: m.media,
                    createdAt: m.createdAt,
                  )
                : m)
            .toList();
      });
    } else if (type == "message_status") {
      // Mise à jour du statut d'un message (ex: SENT → DELIVERED).
      final messageId = e["messageId"] as String?;
      final newStatus = e["status"] as String?;
      if (messageId == null || newStatus == null) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == messageId && _statusRank(newStatus) > _statusRank(m.status)
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
                    media: m.media,
                    createdAt: m.createdAt,
                  )
                : m)
            .toList();
      });
    } else if (type == "message_deleted") {
      final messageId = e["messageId"] as String?;
      final scope = e["scope"] as String? ?? "me";
      if (messageId == null || e["convId"] != widget.convId) return;
      setState(() {
        if (scope == "me") {
          // « Pour moi » : retire le message de ma liste.
          _messages = _messages.where((m) => m.id != messageId).toList();
        } else {
          // « Pour tous » : remplace par un placeholder supprimé.
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
                      createdAt: m.createdAt,
                    )
                  : m)
              .toList();
        }
      });
    }
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
    _myId = context.read<AuthController>().user?.id;
    _baseUrl = context.read<ApiClient>().baseUrl;
    _token = await context.read<TokenStorage>().accessToken;

    // 1) Charge d'abord le cache local (affichage instantané, offline-first).
    final cached = await MessageCache.getConv(widget.convId);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
        _loading = false;
      });
      for (final m in _messages) {
        _cacheMsg(m);
      }
      _scrollToBottom();
    }

    // 2) Synchronise avec le serveur en arrière-plan.
    try {
      final repo = context.read<ChatRepository>();
      final msgs = await repo.getMessages(widget.convId);
      if (!mounted) return;
      final reversed = msgs.reversed.toList();
      // Sauvegarde dans le cache local pour la prochaine fois.
      await MessageCache.putConv(widget.convId, reversed);
      setState(() {
        _messages = reversed;
        _loading = false;
      });
      for (final m in _messages) {
        _cacheMsg(m);
      }
      _markReadRemote();
      _scrollToBottom();
    } catch (_) {
      // Erreur réseau : si on a déjà le cache, on le garde.
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Récupère silencieusement l'état courant et fusionne s'il y a du nouveau.
  /// Repli uniquement : on saute si le temps réel est connecté.
  Future<void> _poll() async {
    if (!mounted || _loading) return;
    if (context.read<RealtimeClient>().connected) return;
    try {
      final repo = context.read<ChatRepository>();
      final latest = (await repo.getMessages(widget.convId)).reversed.toList();
      if (!mounted) return;
      if (_signature(latest) == _signature(_messages)) return; // rien de neuf

      final hadMore = latest.length > _messages.length;
      final atBottom = !_scrollCtrl.hasClients ||
          _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 60;
      setState(() => _messages = latest);
      for (final m in latest) {
        _cacheMsg(m);
      }
      // Un message entrant => on marque comme lu.
      if (hadMore) repo.markRead(widget.convId);
      if (hadMore && atBottom) _scrollToBottom();
    } catch (_) {
      // Erreurs réseau silencieuses : on retentera au prochain tick.
    }
  }

  /// Signature compacte (ids + statuts) pour détecter un changement réel.
  String _signature(List<Message> msgs) =>
      msgs.map((m) => "${m.id}:${m.status}").join("|");

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final rt = context.read<RealtimeClient>();
    final replyId = _replyTo?.id;

    // Voie temps réel : envoi optimiste, réconcilié à l'écho du serveur.
    if (rt.connected) {
      final tempId = "tmp-${DateTime.now().microsecondsSinceEpoch}";
      // Snapshot du message cité pour affichage immédiat côté expéditeur.
      final replyMsg = _replyTo;
      final replySnapshot = replyMsg != null
          ? ReplyPreview(
              id: replyMsg.id,
              senderId: replyMsg.senderId,
              type: replyMsg.type,
              content: replyMsg.isDeleted ? null : replyMsg.content,
              isDeleted: replyMsg.isDeleted,
            )
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
        createdAt: DateTime.now(),
      );
      setState(() {
        _messages = [..._messages, optimistic];
        _replyTo = null;
      });
      _inputCtrl.clear();
      rt.sendMessage(widget.convId, text, tempId, replyToId: replyId);
      _scrollToBottom();
      return;
    }

    // Repli REST si le WebSocket n'est pas disponible.
    setState(() {
      _sending = true;
    });
    try {
      final msg = await context.read<ChatRepository>().sendText(widget.convId, text, replyToId: replyId);
      _cacheMsg(msg);
      _inputCtrl.clear();
      setState(() {
        _messages = [..._messages, msg];
        _replyTo = null;
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      // Ni WS ni REST : on met en outbox (offline-first, style WhatsApp).
      // Le message reste visible avec une icône horloge, envoi automatique
      // dès que la connectivité revient.
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
        createdAt: DateTime.now(),
      );
      _cacheMsg(optimistic);
      _inputCtrl.clear();
      setState(() {
        _messages = [..._messages, optimistic];
        _replyTo = null;
      });
      _scrollToBottom();
      await context.read<Outbox>().enqueue(
            tempId: tempId,
            convId: widget.convId,
            content: text,
            replyToId: replyId,
          );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Active le mode réponse au message donné (swipe ou appui sur "Répondre").
  void _setReplyTo(Message m) {
    setState(() => _replyTo = m);
    FocusScope.of(context).requestFocus(FocusNode());
  }

  // --- Helper : coches de statut (style WhatsApp) ---
  // PENDING → ⏱ (en attente d'envoi via Outbox)
  // SENT → ✓ (gris) | DELIVERED → ✓✓ (gris) | READ → ✓✓ (bleu)
  Widget _statusTicks(String status, Color baseColor) {
    if (status == "PENDING") {
      // Horloge = message en outbox, sera envoyé dès le retour du réseau.
      return Icon(Icons.access_time, size: 13, color: baseColor);
    }
    if (status == "READ") {
      return const Icon(Icons.done_all, size: 15, color: AppColors.tickBlue);
    } else if (status == "DELIVERED") {
      return Icon(Icons.done_all, size: 15, color: baseColor);
    }
    return Icon(Icons.done, size: 15, color: baseColor);
  }

  /// Ordre de priorité des statuts : SENT(0) < DELIVERED(1) < READ(2).
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

  /// Construit la ligne horodatage + coches de statut (réutilisable par toutes les bulles).
  Widget _timestampRow(Message m, bool mine, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_time(m.createdAt), style: TextStyle(fontSize: 10, color: color)),
        if (mine) ...[
          const SizedBox(width: 4),
          _statusTicks(m.status, color),
        ],
      ],
    );
  }

  /// Retrouve un message cité dans la liste locale (pour le scroll-to-message).
  Message? _findMessage(String? id) {
    if (id == null) return null;
    try {
      return _messages.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Met en cache un snapshot d'un message (pour les aperçus de réponse).
  /// Appelée pour CHAQUE message traité → le cache reste à jour et survit
  /// aux réconciliations de _messages (qui remplace les objets en place).
  void _cacheMsg(Message m) {
    _replySnapshots[m.id] = ReplyPreview(
      id: m.id,
      senderId: m.senderId,
      type: m.type,
      content: m.isDeleted ? null : m.content,
      isDeleted: m.isDeleted,
    );
  }

  /// Récupère le snapshot d'un message cité : cache local → serveur → liste live.
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

  /// Fait défiler la liste vers le message cité (clic sur l'aperçu de réponse).
  void _scrollToMessage(String id) {
    final key = _messageKeys[id];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.4,
      );
    }
  }

  /// Détermine le texte d'aperçu selon le type de message cité.
  String _replyPreviewText(Message? original, ReplyPreview? snapshot) {
    if (snapshot != null) {
      if (snapshot.isDeleted) return tr(context, 'message_deleted');
      if (snapshot.content != null) return snapshot.content!;
      return _typeLabel(snapshot.type);
    }
    if (original == null) return '...';
    if (original.isDeleted) return tr(context, 'message_deleted');
    if (original.content != null) return original.content!;
    if (original.media.isNotEmpty) {
      return '📎 ${original.media.first.filename ?? tr(context, 'file')}';
    }
    return _typeLabel(original.type);
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'IMAGE':
        return '📷 ${tr(context, 'photo')}';
      case 'AUDIO':
        return '🎙️ ${tr(context, 'voice_message')}';
      case 'VIDEO':
        return '🎥 ${tr(context, 'video')}';
      case 'FILE':
        return '📎 ${tr(context, 'file')}';
      default:
        return '[${type}]';
    }
  }

  /// Détermine le nom de l'auteur du message cité.
  String _replySenderName(Message? original, ReplyPreview? snapshot) {
    final senderId = snapshot?.senderId ?? original?.senderId;
    if (senderId == null) return tr(context, 'reply_to');
    if (senderId == _myId) return tr(context, 'you');
    return widget.memberNames[senderId] ?? tr(context, 'reply_to');
  }

  /// Construit l'aperçu du message cité (en haut de la bulle, style WhatsApp).
  /// Utilise le snapshot du backend (m.replyTo) qui contient le contenu du message
  /// original — fonctionne même si le message n'est plus chargé localement.
  /// Cliquable : scroll vers le message original si celui-ci est dans la liste.
  Widget _replyPreviewHeader(Message m, bool mine) {
    // Résout le snapshot via le cache local (priorité), le serveur, ou la liste live.
    final snapshot = _resolveReply(m);
    final original = _findMessage(m.replyToId);
    if (snapshot == null && original == null) return const SizedBox.shrink();

    final onColor = mine ? Colors.white : AppColors.ink;
    final barColor = mine ? Colors.white70 : AppColors.terracotta;
    final previewText = _replyPreviewText(original, snapshot);
    final senderName = _replySenderName(original, snapshot);
    final canScroll = original != null;

    return GestureDetector(
      onTap: canScroll ? () => _scrollToMessage(m.replyToId!) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withOpacity(0.15) : AppColors.sand.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: barColor, width: 3)),
        ),
        constraints: const BoxConstraints(maxWidth: 220),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: onColor.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendFile() async {
    if (_uploading) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
    } catch (_) {
      if (mounted) {
        _showError(
          "Sélection de fichier indisponible sur Linux — installe zenity : sudo apt install zenity",
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final mime = _mimeFromName(file.name);
    final msgType = mime.startsWith("image/")
        ? "IMAGE"
        : mime.startsWith("audio/")
            ? "AUDIO"
            : "FILE";
    await _uploadAndSend(bytes, file.name, mime, msgType);
  }

  Future<void> _uploadAndSend(
    List<int> bytes,
    String filename,
    String mime,
    String msgType, {
    int? durationMs,
  }) async {
    setState(() => _uploading = true);

    // Capture reply context BEFORE clearing (for media sends)
    final replyId = _replyTo?.id;
    final replyMsg = _replyTo;
    final replySnapshot = replyMsg != null
        ? ReplyPreview(
            id: replyMsg.id,
            senderId: replyMsg.senderId,
            type: replyMsg.type,
            content: replyMsg.isDeleted ? null : replyMsg.content,
            isDeleted: replyMsg.isDeleted,
          )
        : null;

    // Clear the reply bar immediately (WhatsApp behavior)
    if (mounted) setState(() => _replyTo = null);

    final media = context.read<MediaRepository>();
    final rt = context.read<RealtimeClient>();
    try {
      final uploaded = await media.upload(
        Uint8List.fromList(bytes),
        filename,
        mime,
        durationMs: durationMs,
      );

      if (rt.connected) {
        // WS path: pass replyToId (server will echo full message + replyTo snapshot)
        rt.sendMedia(
          widget.convId,
          uploaded.id,
          msgType,
          "tmp-${DateTime.now().microsecondsSinceEpoch}",
          replyToId: replyId,
        );
      } else {
        // REST fallback: now supports replyToId (backend returns enriched message)
        final msg = await context.read<ChatRepository>().sendMedia(
          widget.convId,
          uploaded.id,
          msgType,
          replyToId: replyId,
        );
        if (mounted) {
          // The returned msg already has replyTo snapshot from backend
          setState(() => _messages = [..._messages, msg]);
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

  void _startRecordTimer() {
    _recordTimer?.cancel();
    _recordDuration = Duration.zero;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _recordDuration = DateTime.now().difference(_recordStarted ?? DateTime.now());
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
    _voiceActive = true; // marque le début de l'interaction (garde-fou anti-race)
    if (!_voiceRecorder.isSupported) {
      _voiceActive = false;
      _showError(tr(context, 'micro_unavailable_platform'));
      return;
    }
    final ok = await _voiceRecorder.start();
    if (!ok || !_voiceActive) {
      // L'utilisateur a relâché avant la fin du démarrage, ou permission refusée.
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
  }

  Future<void> _stopVoiceRecord({bool cancel = false}) async {
    _voiceActive = false; // l'interaction est terminée
    if (!_recording) return;
    _stopRecordTimer();
    setState(() {
      _recording = false;
      _recordLocked = false;
      _recordDuration = Duration.zero;
    });
    if (cancel) {
      _voiceRecorder.cancel();
      return;
    }
    final result = await _voiceRecorder.stop();
    if (result == null || result.bytes.isEmpty) return;
    final ext = kIsWeb ? "webm" : "m4a";
    final mime = kIsWeb ? "audio/webm" : "audio/mp4";
    await _uploadAndSend(
      result.bytes,
      "vocal-${DateTime.now().millisecondsSinceEpoch}.$ext",
      mime,
      "AUDIO",
      durationMs: result.durationMs,
    );
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

  /// Récupère un token FRAIS depuis le stockage sécurisé.
  /// Le token d'accès expire après 15 min — il faut le rafraîchir avant chaque
  /// opération média (téléchargement, lecture image/vidéo) sinon l'API répond 401.
  Future<String> _freshToken() async {
    _token = await context.read<TokenStorage>().accessToken;
    return _token ?? '';
  }

  String _mediaUrl(MessageMedia m) => "$_baseUrl${m.url}?token=${_token ?? ''}";

  String _downloadUrl(MessageMedia m) =>
      "$_baseUrl${m.url}?download=1&token=${_token ?? ''}";

  Future<void> _download(MessageMedia m) async {
    // Token frais obligatoire : l'ancien peut être expiré après 15 min.
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

  /// Ouvre une image en plein écran (visionneuse avec zoom + téléchargement).
  Future<void> _openImageViewer(Message m) async {
    final token = await _freshToken();
    final media = m.media.first;
    final name = media.filename ?? "image-${media.id}";
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          imageUrl: "$_baseUrl${media.url}?token=$token",
          downloadUrl: "$_baseUrl${media.url}?download=1&token=$token",
          filename: name,
        ),
      ),
    );
  }

  /// Ouvre une vidéo dans le lecteur vidéo intégré (plein écran).
  Future<void> _openVideoViewer(Message m) async {
    final token = await _freshToken();
    final media = m.media.first;
    final name = media.filename ?? "video-${media.id}";
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoViewerScreen(
          videoUrl: "$_baseUrl${media.url}?token=$token",
          downloadUrl: "$_baseUrl${media.url}?download=1&token=$token",
          filename: name,
        ),
      ),
    );
  }

  /// Ouvre un PDF dans la visionneuse intégrée (plein écran, style WhatsApp).
  /// Télécharge d'abord le fichier dans le cache app-privé (nécessaire pour
  /// que flutter_pdfview puisse le lire), puis affiche avec navigation par pages.
  Future<void> _openPdfViewer(Message m) async {
    final token = await _freshToken();
    final media = m.media.first;
    final name = media.filename ?? "document-${media.id}.pdf";
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          pdfUrl: "$_baseUrl${media.url}?token=$token",
          downloadUrl: "$_baseUrl${media.url}?download=1&token=$token",
          filename: name,
        ),
      ),
    );
  }

  // Icône + couleur selon l'extension/le type du fichier.
  _FileVisual _fileVisual(MessageMedia m) {
    final ext = _ext(m.filename ?? "");
    final mime = m.mimeType;
    if (mime == "application/pdf" || ext == "pdf") {
      return const _FileVisual(Icons.picture_as_pdf, Color(0xFFD32F2F));
    }
    if (ext == "doc" || ext == "docx") {
      return const _FileVisual(Icons.description, Color(0xFF1565C0));
    }
    if (ext == "xls" || ext == "xlsx" || ext == "csv") {
      return const _FileVisual(Icons.table_chart, Color(0xFF2E7D32));
    }
    if (ext == "ppt" || ext == "pptx") {
      return const _FileVisual(Icons.slideshow, Color(0xFFE64A19));
    }
    if (ext == "zip" || ext == "rar" || ext == "7z") {
      return const _FileVisual(Icons.folder_zip, Color(0xFF6D4C41));
    }
    if (mime.startsWith("audio/")) {
      return const _FileVisual(Icons.audiotrack, Color(0xFF7B1FA2));
    }
    if (mime.startsWith("video/")) {
      return const _FileVisual(Icons.movie, Color(0xFF00838F));
    }
    if (mime.startsWith("text/")) {
      return const _FileVisual(Icons.article, Color(0xFF455A64));
    }
    return const _FileVisual(Icons.insert_drive_file, AppColors.chocolate);
  }

  String _humanSize(int? bytes) {
    if (bytes == null || bytes <= 0) return "";
    const units = ["o", "Ko", "Mo", "Go"];
    var size = bytes.toDouble();
    var u = 0;
    while (size >= 1024 && u < units.length - 1) {
      size /= 1024;
      u++;
    }
    final v = u == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return "$v ${units[u]}";
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

  void _showError(String m) => showAppSnackBar(m);

  // --- Suppression de message ---

  Future<void> _deleteMessage(Message m) async {
    final canDeleteForAll = m.senderId == _myId && !m.isDeleted;
    final scope = await _showDeleteDialog(canDeleteForAll);
    if (scope == null || !mounted) return;

    final rt = context.read<RealtimeClient>();
    try {
      if (rt.connected) {
        rt.deleteMessage(m.id, scope: scope);
      } else {
        await context.read<ChatRepository>().deleteMessage(widget.convId, m.id, scope: scope);
      }
      if (!mounted) return;
      // Mise à jour optimiste de l'UI.
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
                      createdAt: m.createdAt,
                    )
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

  /// Affiche le dialogue de choix : « Pour moi » / « Pour tous ». Retourne le scope choisi.
  Future<String?> _showDeleteDialog(bool canDeleteForAll) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.chocolate),
              title: Text(tr(context, 'delete_for_me')),
              onTap: () => Navigator.pop(ctx, "me"),
            ),
            if (canDeleteForAll)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(tr(context, 'delete_for_everyone')),
                onTap: () => Navigator.pop(ctx, "everyone"),
              ),
          ],
        ),
      ),
    );
  }

  // --- Transfert de message ---

  Future<void> _forwardMessage(Message m) async {
    final conversations = await context.read<ChatRepository>().listConversations();
    if (!mounted) return;

    final picked = <String>{};
    await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ForwardPicker(
        conversations: conversations.where((c) => c.id != widget.convId).toList(),
        title: tr(context, 'forward_to'),
      ),
    ).then((result) {
      if (result != null) picked.addAll(result);
    });

    if (picked.isEmpty || !mounted) return;

    final rt = context.read<RealtimeClient>();
    try {
      if (rt.connected) {
        rt.forwardMessage(m.id, picked.toList());
      } else {
        await context.read<ChatRepository>().forwardMessage(widget.convId, m.id, picked.toList());
      }
      if (mounted) showAppSnackBar(tr(context, 'forwarded_success'));
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(tr(context, 'send_failed'));
    }
  }

  /// Affiche le menu contextuel (appui long sur un message).
  void _showMessageOptions(Message m) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!m.isDeleted) ...[
              ListTile(
                leading: const Icon(Icons.reply, color: AppColors.terracotta),
                title: Text(tr(context, 'reply')),
                onTap: () {
                  Navigator.pop(ctx);
                  _setReplyTo(m);
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward, color: AppColors.forest),
                title: Text(tr(context, 'forward')),
                onTap: () {
                  Navigator.pop(ctx);
                  _forwardMessage(m);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.chocolate),
                title: Text(tr(context, 'copy')),
                onTap: () {
                  Navigator.pop(ctx);
                  if (m.content != null) {
                    Clipboard.setData(ClipboardData(text: m.content!));
                    showAppSnackBar(tr(context, 'copied'));
                  }
                },
              ),
            ],
            ListTile(
              leading: Icon(m.isDeleted ? Icons.delete_outline : Icons.delete,
                  color: Colors.red),
              title: Text(tr(context, 'delete')),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMessage(m);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startCall(String type) async {
    final cc = context.read<CallController>();
    try {
      await cc.startOutgoing(widget.convId, type, widget.title);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ActiveCallScreen(),
        ),
      );
    } on StateError catch (_) {
      _showError("Tu es déjà en appel");
    } catch (e) {
      // Affiche l'erreur réelle au lieu d'un message générique
      final msg = e.toString();
      if (msg.contains("PERMISSION_DENIED")) {
        _showError("Micro/caméra requis. Accorde les permissions dans les réglages.");
      } else if (msg.contains("409") || msg.contains("BUSY")) {
        _showError("Impossible de démarrer l'appel. Réessaie dans un instant.");
      } else {
        _showError("Erreur d'appel : vérifie ta connexion et réessaie.");
      }
    }
  }

  /// AppBar personnalisée façon WhatsApp :
  /// [avatar][titre / statut clickable]  [📞][🎥]
  ///
  /// - Tap sur l'avatar → visualiseur plein écran
  /// - Tap sur le nom → écran détails contact (uniquement pour DM)
  PreferredSizeWidget _whatsappAppBar() {
    return AppBar(
      backgroundColor: AppColors.terracotta,
      foregroundColor: Colors.white,
      leadingWidth: 40,
      titleSpacing: 0,
      title: InkWell(
        onTap: widget.isGroup ? null : _openContactInfo,
        child: Row(
          children: [
            GestureDetector(
              onTap: _openAvatarViewer,
              child: AvatarCircle(
                name: widget.title,
                avatarUrl: widget.avatarUrl,
                radius: 18,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (!widget.isGroup && widget.otherStatusMsg?.isNotEmpty == true)
                    Text(
                      widget.otherStatusMsg!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    )
                  else if (widget.isGroup)
                    Text(
                      "${widget.memberNames.length} membres",
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: widget.isGroup ? "Appel groupe vidéo" : "Appel vidéo",
          icon: const Icon(Icons.videocam),
          onPressed: () => _startCall("VIDEO"),
        ),
        IconButton(
          tooltip: widget.isGroup ? "Appel groupe audio" : "Appel audio",
          icon: const Icon(Icons.call),
          onPressed: () => _startCall("AUDIO"),
        ),
      ],
    );
  }

  void _openAvatarViewer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvatarViewerScreen(
          name: widget.title,
          avatarUrl: widget.avatarUrl,
        ),
      ),
    );
  }

  void _openContactInfo() {
    // Uniquement pour les DM (les groupes n'ont pas d'écran contact-info).
    if (widget.isGroup) return;
    final otherId = widget.otherUserId;
    if (otherId == null) {
      // Fallback : au moins ouvrir le viewer sur l'avatar
      _openAvatarViewer();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactInfoScreen(
          userId: otherId,
          name: widget.title,
          publicNumber: widget.otherPublicNumber ?? "",
          avatarUrl: widget.avatarUrl,
          statusMsg: widget.otherStatusMsg,
          convId: widget.convId,
          contactId: widget.contactId,
          isBlocked: widget.isBlocked,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AuthController>().user?.id;
    return Scaffold(
      appBar: _whatsappAppBar(),
      body: MotifBackground(
        overlayOpacity: 0.85,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.terracotta))
                  : _messages.isEmpty
                      ? Center(child: Text(tr(context, 'no_messages')))
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _bubble(_messages[i], _messages[i].senderId == myId),
                        ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Message m, bool mine) {
    final isImage = m.type == "IMAGE" && m.media.isNotEmpty;
    final isVideo = m.type == "VIDEO" && m.media.isNotEmpty;
    final isFile = m.type == "FILE" && m.media.isNotEmpty;
    final isAudio = m.type == "AUDIO" && m.media.isNotEmpty;
    final senderLabel = widget.isGroup && !mine
        ? (widget.memberNames[m.senderId] ?? "Membre")
        : null;
    return Align(
      key: _messageKeys.putIfAbsent(m.id, () => GlobalKey()),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (senderLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                senderLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.forest,
                ),
              ),
            ),
        _SwipeToReply(
          onReply: () => _setReplyTo(m),
          child: GestureDetector(
          onLongPress: () => _showMessageOptions(m),
          child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        // Image : marge interne fine pour une vignette quasi pleine bulle (style WhatsApp).
        padding: isImage
            ? const EdgeInsets.all(3)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? AppColors.terracotta : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: mine ? null : Border.all(color: AppColors.sand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Aperçu du message cité (si réponse)
            if (m.replyToId != null && !m.isDeleted)
              _replyPreviewHeader(m, mine),
            // Contenu de la bulle
            m.isDeleted
                ? _deletedBubble(m, mine)
                : isImage
                    ? _imageBubble(m, mine)
                    : isVideo
                        ? _videoBubble(m, mine)
                        : isFile
                            ? _fileBubble(m, mine)
                            : isAudio
                                ? _audioBubble(m, mine)
                                : _textBubble(m, mine),
          ],
        ),
          ), // Container
        ), // GestureDetector
        ), // _SwipeToReply
        ],
      ),
    );
  }

  // Placeholder pour un message supprimé pour tous (style WhatsApp).
  Widget _deletedBubble(Message m, bool mine) {
    final onSub = mine ? Colors.white70 : Colors.black45;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: onSub),
            const SizedBox(width: 6),
            Text(
              tr(context, 'message_deleted'),
              style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: onSub),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _time(m.createdAt),
          style: TextStyle(fontSize: 10, color: onSub),
        ),
      ],
    );
  }

  // Vignette image avec horodatage + accusés et bouton de téléchargement.
  Widget _imageBubble(Message m, bool mine) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _openImageViewer(m),
            onLongPress: () => _showMessageOptions(m),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: AuthNetworkImage(
                url: "$_baseUrl${m.media.first.url}",
                token: _token,
                width: 274,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _download(m.media.first),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.download, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _timestampRow(m, mine, Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Vignette vidéo cliquable avec bouton play → ouvre le lecteur intégré.
  Widget _videoBubble(Message m, bool mine) {
    final onSub = mine ? Colors.white70 : Colors.black45;
    return GestureDetector(
      onTap: () => _openVideoViewer(m),
      onLongPress: () => _showMessageOptions(m),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 274),
              child: Container(
                color: Colors.black87,
                width: 274,
                height: 200,
                child: const Center(
                  child: Icon(Icons.movie, size: 48, color: Colors.white38),
                ),
              ),
            ),
            // Bouton play central
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                ),
              ),
            ),
            // Bouton télécharger
            Positioned(
              right: 6,
              top: 6,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _download(m.media.first),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.download, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
            // Horodatage
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _timestampRow(m, mine, Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pièce jointe non-image : icône d'extension + nom + taille + téléchargement.
  Widget _fileBubble(Message m, bool mine) {
    final media = m.media.first;
    final _FileVisual visual = _fileVisual(media);
    final name = media.filename ?? tr(context, 'file');
    final ext = _ext(name);
    final size = _humanSize(media.sizeBytes);
    final onText = mine ? Colors.white : AppColors.ink;
    final onSub = mine ? Colors.white70 : Colors.black45;
    final isPdf = media.mimeType == "application/pdf" || ext.toLowerCase() == "pdf";
    return InkWell(
      // Tap sur PDF → viewer intégré. Tap sur autre fichier → téléchargement direct.
      onTap: () => isPdf ? _openPdfViewer(m) : _download(media),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visual.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(visual.icon, color: visual.color, size: 26),
                    if (ext.isNotEmpty)
                      Positioned(
                        bottom: 2,
                        child: Text(
                          ext.toUpperCase(),
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            color: visual.color,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onText, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (size.isNotEmpty)
                          Text(size, style: TextStyle(fontSize: 11, color: onSub)),
                        if (size.isNotEmpty) const SizedBox(width: 8),
                        Icon(Icons.download, size: 14, color: onSub),
                        const SizedBox(width: 2),
                        Text(tr(context, 'download'),
                            style: TextStyle(fontSize: 11, color: onSub)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _timestampRow(m, mine, onSub),
        ],
      ),
    );
  }

  // Message vocal : bouton lecture/pause réactif + barre de progression (style WhatsApp).
  Widget _audioBubble(Message m, bool mine) {
    final media = m.media.first;
    final url = _mediaUrl(media);
    final totalDuration =
        media.durationMs != null ? Duration(milliseconds: media.durationMs!) : null;
    final secs = totalDuration?.inSeconds;
    final onSub = mine ? Colors.white70 : Colors.black45;
    final accent = mine ? Colors.white : AppColors.terracotta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<AudioPlaybackState>(
          valueListenable: InlineAudioPlayer.state,
          builder: (context, audioState, _) {
            final isActive = audioState.url == url;
            final isPlaying = isActive && audioState.isPlaying;

            double progress = 0;
            if (isActive) {
              final dur = audioState.duration ?? totalDuration;
              if (dur != null && dur.inMilliseconds > 0) {
                progress = (audioState.position.inMilliseconds /
                        dur.inMilliseconds)
                    .clamp(0.0, 1.0);
              }
            }

            return InkWell(
              onTap: () =>
                  InlineAudioPlayer.toggle(url, totalDuration: totalDuration),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: accent.withOpacity(0.15),
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: onSub.withOpacity(0.3),
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        secs != null
                            ? "${secs}s"
                            : tr(context, 'voice_message'),
                        style: TextStyle(fontSize: 12, color: onSub),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.mic, size: 16, color: onSub),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        _timestampRow(m, mine, onSub),
      ],
    );
  }

  Future<void> _translateMessage(Message m) async {
    final text = (m.content ?? '').trim();
    if (text.isEmpty) return;
    final locale = context.read<LocaleController>().languageCode;
    // Si déjà traduit, on toggle (masquer)
    if (_translations.containsKey(m.id)) {
      setState(() => _translations.remove(m.id));
      return;
    }
    if (_translating.contains(m.id)) return;
    setState(() => _translating.add(m.id));
    try {
      // Détection simple : si l'utilisateur est en FR, on traduit vers FR, sinon EN
      // source = auto
      final translated = await _translateService.translate(
        text: text,
        target: locale,
        source: 'auto',
      );
      if (!mounted) return;
      setState(() => _translations[m.id] = translated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'translation_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _translating.remove(m.id));
    }
  }

  Widget _textBubble(Message m, bool mine) {
    final translated = _translations[m.id];
    final isTranslating = _translating.contains(m.id);
    final onTextColor = mine ? Colors.white : AppColors.ink;
    final onSubColor = mine ? Colors.white70 : Colors.black45;

    return GestureDetector(
      onTap: m.type == 'TEXT' && (m.content ?? '').isNotEmpty
          ? () => _translateMessage(m)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.content ?? "[${m.type}]",
            style: TextStyle(color: onTextColor),
          ),
          if (translated != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: mine ? Colors.white.withOpacity(0.15) : AppColors.sand.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.translate, size: 12, color: onSubColor),
                      const SizedBox(width: 4),
                      Text(
                        tr(context, 'translated'),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: onSubColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    translated,
                    style: TextStyle(fontSize: 13, color: onTextColor, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
          if (isTranslating) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: onSubColor),
                ),
                const SizedBox(width: 6),
                Text(tr(context, 'translating'), style: TextStyle(fontSize: 10, color: onSubColor)),
              ],
            ),
          ],
          if (!isTranslating && translated == null && m.type == 'TEXT')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr(context, 'translate'),
                style: TextStyle(fontSize: 10, color: onSubColor.withOpacity(0.8), fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 2),
          _timestampRow(m, mine, onSubColor),
        ],
      ),
    );
  }

  String _time(DateTime d) {
    final l = d.toLocal();
    return "${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}";
  }

  Widget _composer() {
    // ---- ÉTAT VERROUILLÉ : l'utilisateur a slidé vers le haut ----
    // L'enregistrement continue sans maintenir le doigt. Boutons envoyer/annuler.
    if (_recordLocked) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(8),
          color: AppColors.cream,
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _stopVoiceRecord(cancel: true),
                child: CircleAvatar(
                  backgroundColor: Colors.red.shade400,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.fiber_manual_record,
                          color: Colors.red, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(_recordDuration),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.lock, color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        tr(context, 'recording_locked'),
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _uploading ? null : () => _stopVoiceRecord(),
                child: CircleAvatar(
                  backgroundColor: AppColors.terracotta,
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ---- ÉTAT NORMAL OU ENREGISTREMENT (doigt maintenu) ----
    // On utilise Offstage pour cacher les boutons 📎 et 📤 pendant l'enregistrement
    // SANS modifier la structure du Row : le GestureDetector du micro reste ainsi
    // au MÊME index dans l'arbre, ce qui préserve le geste long-press à travers
    // le rebuild de setState (sinon onLongPressEnd ne se déclencherait jamais).
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barre de prévisualisation quand on répond à un message
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppColors.cream,
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.terracotta,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyTo!.senderId == _myId
                              ? tr(context, 'you')
                              : (widget.memberNames[_replyTo!.senderId] ?? tr(context, 'reply_to')),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.terracotta,
                          ),
                        ),
                        Text(
                          _replyTo!.isDeleted
                              ? tr(context, 'message_deleted')
                              : (_replyTo!.content ??
                                  (_replyTo!.media.isNotEmpty
                                      ? '📎 ${_replyTo!.media.first.filename ?? tr(context, 'file')}'
                                      : '...')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _replyTo = null),
                    child: const Icon(Icons.close, size: 20, color: Colors.black54),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            color: AppColors.cream,
            child: Row(
              children: [
                // Bouton pièce jointe — Offstage préserve la structure du Row
                Offstage(
                  offstage: _recording,
                  child: IconButton(
                    tooltip: tr(context, 'attach_file'),
                    icon: _uploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.attach_file, color: AppColors.chocolate),
                    onPressed: _uploading ? null : _pickAndSendFile,
                  ),
                ),
                // Champ texte OU barre d'enregistrement (même slot Expanded)
                Expanded(
                  child: _recording
                      ? _recordingBar()
                      : TextField(
                          controller: _inputCtrl,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: tr(context, 'write_message'),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                // Bouton micro — TOUJOURS à cet index (stable pour le gesture)
                _micButton(),
                // Bouton envoyer — Offstage préserve la structure du Row
                Offstage(
                  offstage: _recording,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: AppColors.terracotta,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _sending ? null : _send,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Barre d'enregistrement affichée pendant que le doigt est maintenu.
  Widget _recordingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_recordDuration),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.red.shade700,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(context, 'slide_up_to_lock'),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ),
          const Icon(Icons.keyboard_arrow_up, color: Colors.black38, size: 20),
        ],
      ),
    );
  }

  // Bouton micro avec détection de geste long-press + slide-to-lock.
  // Un Stack superpose une icône de verrouillage au-dessus du micro pendant l'enregistrement.
  Widget _micButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _startVoiceRecord(),
      onLongPressMoveUpdate: (details) {
        // Slide vers le haut (> 60 px) → verrouillage.
        if (details.offsetFromOrigin.dy < -60 && _recording && !_recordLocked) {
          setState(() => _recordLocked = true);
        }
      },
      onLongPressEnd: (_) {
        // Relâche sans verrouillage → envoi automatique.
        if (_recording && !_recordLocked) {
          _stopVoiceRecord();
        }
      },
      onLongPressCancel: () {
        if (_recording && !_recordLocked) {
          _stopVoiceRecord(cancel: true);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            backgroundColor: _recording ? Colors.red : AppColors.forest,
            child: Icon(
              _recording ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 22,
            ),
          ),
          // Icône de verrouillage au-dessus du micro pendant l'enregistrement
          if (_recording)
            Positioned(
              top: -30,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_open, color: Colors.white, size: 14),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileVisual {
  final IconData icon;
  final Color color;
  const _FileVisual(this.icon, this.color);
}

/// Widget de swipe-to-reply : glisse horizontalement une bulle pour répondre.
/// L'utilisateur fait glisser la bulle vers la droite ; une icône de réponse
/// apparaît, et si le seuil est atteint, le callback onReply est déclenché.
/// La bulle revient ensuite en place avec une animation.
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
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
    // Pendant l'animation de retour : interpole de _dragExtent vers 0.
    final offset = _ctrl.isAnimating ? _dragExtent * (1 - _ctrl.value) : _dragExtent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        setState(() {
          // On ne permet que de glisser vers la droite (positif).
          _dragExtent = (_dragExtent + d.delta.dx).clamp(0.0, _threshold * 1.4);
        });
      },
      onHorizontalDragEnd: (_) {
        if (_dragExtent >= _threshold) {
          widget.onReply();
        }
        _ctrl.forward(from: 0);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: Offset(offset, 0),
            child: widget.child,
          ),
          if (offset > 5)
            Positioned(
              left: offset - 28,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(Icons.reply_rounded, color: Colors.grey[400], size: 22),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sélecteur de conversations pour le transfert de message (multi-sélection).
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(widget.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: Text(
                    _selected.isEmpty
                        ? ''
                        : '${_selected.length}',
                    style: TextStyle(
                      color: _selected.isEmpty ? Colors.grey : AppColors.terracotta,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Liste des conversations (hauteur limitée)
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
                    backgroundColor: isSelected ? AppColors.terracotta : AppColors.sand,
                    child: Icon(
                      isSelected ? Icons.check : (conv.isGroup ? Icons.group : Icons.person),
                      color: isSelected ? Colors.white : AppColors.chocolate,
                    ),
                  ),
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
              },
            ),
          ),
          // Bouton de validation
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.terracotta,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, _selected),
                  icon: const Icon(Icons.send),
                  label: Text(tr(context, 'send')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
