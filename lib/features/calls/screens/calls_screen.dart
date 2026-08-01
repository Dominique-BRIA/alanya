import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/call_cache.dart';
import '../../../models/call_record.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/motif_background.dart';
import '../../../widgets/multi_select_mixin.dart';
import '../call_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    context.read<CallController>().addListener(_onCallActivity);
  }

  @override
  void dispose() {
    context.read<CallController>().removeListener(_onCallActivity);
    super.dispose();
  }

  void _onCallActivity() {
    final busy = context.read<CallController>().isBusy;
    if (_wasBusy && !busy) _load();
    _wasBusy = busy;
  }

  Future<void> _load() async {
    final cached = await CallCache.getAll();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _calls = _sortAndLimit(cached);
        _error = false;
      });
    }
    try {
      final calls = await context.read<CallsRepository>().history();
      if (!mounted) return;
      setState(() {
        _calls = _sortAndLimit(calls);
        _error = false;
      });
      await CallCache.putAll(calls);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _calls == null || _calls!.isEmpty);
      }
    }
  }

  List<CallRecord> _sortAndLimit(List<CallRecord> calls) {
    final sorted = List<CallRecord>.from(calls);
    sorted.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (sorted.length > 20) return sorted.take(20).toList();
    return sorted;
  }

  /// Statut précis selon la nuance demandée :
  /// - A appelle B, B ne décroche pas : chez A "Appel sans réponse", chez B "Appel manqué"
  /// - B rejette : chez A "Appel refusé", chez B "Appel rejeté"
  String _preciseStatus(CallRecord c) {
    final s = c.status;
    final outgoing = c.isOutgoing;

    switch (s) {
      case "MISSED":
        // Backend MISSED : si sortant = pas de réponse, si entrant = manqué
        return outgoing ? "Appel sans réponse" : "Appel manqué";
      case "REJECTED":
      case "DECLINED":
        // Si j'ai rejeté (entrant) vs on m'a refusé (sortant)
        return outgoing ? "Appel refusé" : "Appel rejeté";
      case "NO_ANSWER":
        return outgoing ? "Appel sans réponse" : "Appel manqué";
      case "BUSY":
        return "Occupé";
      case "ENDED":
        if (c.durationSec != null && c.durationSec! > 0) {
          return outgoing ? "Appel sortant" : "Appel entrant";
        } else {
          // Terminé sans durée = souvent sans réponse
          return outgoing ? "Appel sans réponse" : "Appel manqué";
        }
      case "RINGING":
        return outgoing ? "Appel sortant" : "Appel entrant";
      case "ONGOING":
        return "En cours";
      default:
        return s;
    }
  }

  IconData _iconFor(CallRecord c) {
    final s = c.status;
    final outgoing = c.isOutgoing;

    if (s == "MISSED") {
      return outgoing ? Icons.call_made : Icons.call_missed;
    }
    if (s == "REJECTED" || s == "DECLINED") {
      return outgoing ? Icons.call_made : Icons.call_received;
    }
    if (s == "BUSY") {
      return Icons.block;
    }
    if (s == "NO_ANSWER") {
      return outgoing ? Icons.call_made : Icons.call_missed;
    }
    // ENDED
    if (s == "ENDED") {
      if (c.durationSec != null && c.durationSec! > 0) {
        return outgoing ? Icons.call_made : Icons.call_received;
      } else {
        return outgoing ? Icons.call_made : Icons.call_missed;
      }
    }
    // RINGING, ONGOING
    return outgoing ? Icons.call_made : Icons.call_received;
  }

  Color _colorFor(CallRecord c, BuildContext context) {
    final s = c.status;
    if (s == "MISSED" || s == "NO_ANSWER") {
      return dangerOf(context);
    }
    if (s == "REJECTED" || s == "DECLINED" || s == "BUSY") {
      // Refusé / Occupé en rouge si entrant manqué/rejeté, sinon neutre ?
      // On met rouge pour tout ce qui n'est pas abouti côté receveur
      if (!c.isOutgoing) return dangerOf(context);
      return mutedOf(context, Colors.black54);
    }
    return positiveOf(context);
  }

  String _formatDateTime(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}";
  }

  String _formatDuration(int? sec) {
    if (sec == null || sec <= 0) return "";
    final m = sec ~/ 60;
    final s = sec % 60;
    return "${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}";
  }

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

    // Pour les appels sans réponse / manqués, pas de durée
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
              color: (c.status == "MISSED" ||
                      (c.status == "ENDED" && (c.durationSec == null || c.durationSec == 0) && !c.isOutgoing))
                  ? dangerOf(context, Colors.red.shade700)
                  : mutedOf(context, Colors.black54),
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
          : (c.convId == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        convId: c.convId!,
                        title: c.peerName,
                        isGroup: c.isGroup,
                      ),
                    ),
                  )),
    );
  }
}
