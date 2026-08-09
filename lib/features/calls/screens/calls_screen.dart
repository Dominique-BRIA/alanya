import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/call_cache.dart';
import '../../../core/call_status.dart';
import '../../../core/realtime_client.dart';
import '../../../models/call_record.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/motif_background.dart';
import '../../../widgets/multi_select_mixin.dart';
import '../call_controller.dart';
import '../ouvrir_appel_en_cours.dart';
import '../calls_repository.dart';
import 'dialer_screen.dart';
import '../../chat/screens/chat_screen.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen>
    with MultiSelectMixin<CallsScreen> {
  List<CallRecord>? _calls;
  bool _error = false;
  bool _wasBusy = false;

  StreamSubscription<Map<String, dynamic>>? _rtSub;

  @override
  void initState() {
    super.initState();
    _load();
    context.read<CallController>().addListener(_onCallActivity);
    // Cet écran ne suivait QUE le CallController, donc uniquement les appels
    // passés depuis cet appareil. Un appel manqué pendant qu'on regardait la
    // liste n'y apparaissait jamais de lui-même.
    _rtSub = context.read<RealtimeClient>().events.listen((e) {
      if (!mounted) return;
      final t = e["type"];
      if (t == "call_ended") {
        final brut = e["call"];
        if (brut is Map) {
          _integreAppel(CallRecord.fromJson(Map<String, dynamic>.from(brut)));
        }
      } else if (t == "ws_connected") {
        // La coupure a pu masquer des appels : les événements ne se rejouent pas.
        _load();
      }
    });
  }

  /// Insère un appel poussé par le serveur, sans requête. Remplace par
  /// identifiant : le même appel change d'état plusieurs fois.
  void _integreAppel(CallRecord c) {
    final cc = context.read<CallController>();
    final ajuste = cc.adjustCall(c);
    final liste = List<CallRecord>.from(_calls ?? []);
    final i = liste.indexWhere((x) => x.id == ajuste.id);
    if (i >= 0) {
      liste[i] = ajuste;
    } else {
      liste.add(ajuste);
    }
    setState(() => _calls = CallStatusFormalisme.sortAndLimit20(liste));
    CallCache.putAll(liste);
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    context.read<CallController>().removeListener(_onCallActivity);
    super.dispose();
  }

  void _onCallActivity() {
    final busy = context.read<CallController>().isBusy;
    if (_wasBusy && !busy) _load();
    _wasBusy = busy;
  }

  Future<void> _load() async {
    final cc = context.read<CallController>();
    final cached = await CallCache.getAll();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _calls = CallStatusFormalisme.sortAndLimit20(cc.adjustCalls(cached));
        _error = false;
      });
    }
    try {
      final calls = await context.read<CallsRepository>().history();
      if (!mounted) return;
      final ajustes = cc.adjustCalls(calls);
      setState(() {
        _calls = CallStatusFormalisme.sortAndLimit20(ajustes);
        _error = false;
      });
      await CallCache.putAll(ajustes);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _calls == null || _calls!.isEmpty);
      }
    }
  }

  // Formalisme standard centralisé
  String _preciseStatus(CallRecord c) => CallStatusFormalisme.preciseLabel(c);
  IconData _iconFor(CallRecord c) => CallStatusFormalisme.iconFor(c);
  Color _colorFor(CallRecord c, BuildContext context) => CallStatusFormalisme.colorFor(c, danger: dangerOf(context), positive: positiveOf(context));
  String _formatDateTime(DateTime dt) => CallStatusFormalisme.formatDateTime(dt);
  String _formatDuration(int? sec) => CallStatusFormalisme.formatDuration(sec);

  Future<void> _deleteSelected() async {
    final count = selectedCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Supprimer $count appel(s) ?"),
        content: const Text("Cette action est irréversible."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Supprimer",
                  style: TextStyle(color: dangerOf(context)))),
        ],
      ),
    );
    if (ok != true) return;

    final repo = context.read<CallsRepository>();
    for (final id in selectedIds) {
      try {
        await repo.deleteCall(id);
      } catch (_) {}
    }
    clearSelection();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return MotifBackground(
      overlayOpacity: 0.92,
      plainInDark: true,
      child: isSelecting
          ? Scaffold(
              appBar: selectAppBar(
                title: "Appels",
                onDelete: _deleteSelected,
                onCancel: clearSelection,
                onSelectAll: () => selectAll(
                    (_calls ?? []).map((c) => c.id).toList()),
              ),
              body: RefreshIndicator(
                onRefresh: _load,
                child: _buildBody(),
              ),
            )
          : Scaffold(
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Appels"),
                    if (_calls != null)
                      Text("${_calls!.length} derniers appels",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
              body: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: _load,
                    child: _buildBody(),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      backgroundColor: AlanyaColors.logoVert,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DialerScreen()),
                      ),
                      child: const Icon(Icons.phone, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_calls == null && !_error) {
      return ListView(children: [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: accentOf(context))),
      ]);
    }
    if (_error) {
      return ListView(children: const [
        SizedBox(height: 80),
        Center(child: Text("Erreur de chargement. Tire pour réessayer.")),
      ]);
    }
    final calls = _calls ?? [];
    if (calls.isEmpty) {
      return ListView(children: [
        SizedBox(height: 100),
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Aucun appel pour le moment.\nLance un appel depuis une discussion.",
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedOf(context, Colors.black54)),
            ),
          ),
        ),
      ]);
    }
    return ListView.separated(
      itemCount: calls.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _tile(calls[i]),
    );
  }

  Widget _tile(CallRecord c) {
    final icon = _iconFor(c);
    final color = _colorFor(c, context);
    final status = _preciseStatus(c);
    final dateStr = _formatDateTime(c.startedAt);
    final dur = _formatDuration(c.durationSec);

    final subtitleText = StringBuffer()
      ..write(status)
      ..write(" · $dateStr");
    if (dur.isNotEmpty) {
      subtitleText.write(" · $dur");
    }
    if (c.isGroup) {
      subtitleText.write(" · Groupe");
    }

    return ListTile(
      leading: isSelecting
          ? selectCheckbox(c.id)
          : (c.isGroup
              ? CircleAvatar(
                  backgroundColor: AlanyaColors.gold,
                  child: const Icon(Icons.groups,
                      color: Colors.white, size: 20),
                )
              : AvatarCircle(
                  name: c.peerName,
                  avatarUrl: c.peerAvatarUrl,
                  radius: 22,
                  backgroundColor: AlanyaColors.gold,
                )),
      title: Row(
        children: [
          Expanded(
            child: Text(c.peerName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (c.type == "VIDEO")
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.videocam,
                  size: 14,
                  color: themed(context,
                      light: AlanyaColors.grey400,
                      dark: AlanyaColors.craie2)),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitleText.toString(),
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: isSelecting
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Icon(Icons.call,
                    color: themed(context,
                        light: AlanyaColors.terracotta,
                        dark: AlanyaColors.terracottaNuit),
                    size: 18),
              ],
            ),
      onLongPress: () => startSelecting(c.id),
      onTap: isSelecting
          ? () => toggleSelect(c.id)
          : () {
              // Un appel en cours ramène à son écran plutôt qu'à la
              // conversation : c'est ce qu'on cherche en appuyant dessus.
              if (ouvrirSiAppelEnCours(context, c.id)) return;
              // Garde la condition d'avant : sans conversation, il n'y a rien
              // à ouvrir. L'entrée reste alors inerte.
              if (c.convId == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    convId: c.convId!,
                    title: c.peerName,
                    isGroup: c.isGroup,
                  ),
                ),
              );
            },
    );
  }
}
