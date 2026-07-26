import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/alanya_theme.dart';
import '../../../widgets/motif_background.dart';
import '../../../widgets/multi_select_mixin.dart';
import '../../../models/meeting.dart';
import '../meetings_repository.dart';
import 'create_meeting_screen.dart';
import 'meeting_detail_screen.dart';

/// Onglet "Réunions" intégré dans la barre de navigation du HomeScreen.
class MeetingsScreen extends StatefulWidget {
  const MeetingsScreen({super.key});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen>
    with MultiSelectMixin<MeetingsScreen> {
  List<Meeting>? _meetings;
  bool _error = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<MeetingsRepository>().fetchMeetings();
      if (!mounted) return;
      setState(() {
        _meetings = list;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateMeetingScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _deleteSelected() async {
    final count = selectedCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Supprimer $count réunion(s) ?"),
        content: const Text("Seules les réunions terminées peuvent être supprimées."),
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

    final repo = context.read<MeetingsRepository>();
    for (final id in selectedIds) {
      try {
        await repo.deleteMeeting(int.parse(id));
      } catch (_) {}
    }
    clearSelection();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return MotifBackground(
      overlayOpacity: 0.92,
      child: isSelecting
          ? Scaffold(
              appBar: selectAppBar(
                title: "Réunions",
                onDelete: _deleteSelected,
                onCancel: clearSelection,
                onSelectAll: () => selectAll(
                    (_meetings ?? [])
                        .where((m) => m.isFinished)
                        .map((m) => m.idMeeting.toString())
                        .toList()),
              ),
              body: RefreshIndicator(
                onRefresh: _load,
                child: _buildList(),
              ),
            )
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: _buildList(),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    backgroundColor: accentOf(context),
                    onPressed: _create,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildList() {
    if (_meetings == null && !_error) {
      return Center(
        child: CircularProgressIndicator(color: accentOf(context)),
      );
    }
    if (_error) {
      return ListView(children: const [
        SizedBox(height: 80),
        Center(child: Text("Erreur de chargement. Tire pour réessayer.")),
      ]);
    }

    final meetings = _meetings ?? [];
    if (meetings.isEmpty) {
      return ListView(children: [
        SizedBox(height: 100),
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_outlined, size: 64, color: AlanyaColors.gold),
                SizedBox(height: 12),
                Text(
                  "Aucune réunion.\nAppuie sur + pour créer une réunion audio ou vidéo.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedOf(context, Colors.black54)),
                ),
              ],
            ),
          ),
        ),
      ]);
    }

    final active = meetings.where((m) => !m.isFinished).toList();
    final ended = meetings.where((m) => m.isFinished).toList();

    return ListView(
      children: [
        if (active.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text("En cours / À venir",
                style: TextStyle(
                    color: mutedOf(context, Colors.black54), fontWeight: FontWeight.bold)),
          ),
          ...active.map(_tile),
        ],
        if (ended.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Row(
              children: [
                Text("Terminées",
                    style: TextStyle(
                        color: faintOf(context, Colors.black38), fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!isSelecting && ended.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      // Sélectionne toutes les réunions terminées
                      for (final m in ended) {
                        startSelecting(m.idMeeting.toString());
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text("Supprimer", style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: dangerOf(context, Colors.red.shade400),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
          ),
          ...ended.map(_tile),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _tile(Meeting m) {
    final icon = m.isVideo ? Icons.videocam : Icons.call;
    final typeLabel = m.isVideo ? "Vidéo" : "Audio";
    final statusLabel =
        m.isFinished ? "Terminée" : "${m.connectedCount} connecté(s)";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: isSelecting
            ? selectCheckbox(m.idMeeting.toString())
            : CircleAvatar(
                backgroundColor:
                    m.isFinished ? themed(context, light: Colors.grey.shade300, dark: AlanyaColors.nuit3) : positiveOf(context),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
        title: Text(m.objet,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: m.isFinished ? TextDecoration.lineThrough : null,
            )),
        subtitle: Text(
          "$typeLabel · $statusLabel · ${_formatDate(m.startTime)}",
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isSelecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 16, color: mutedOf(context, AlanyaColors.grey400)),
                  const SizedBox(width: 4),
                  Text(
                    "${m.participants.length}",
                    style:
                        TextStyle(fontSize: 13, color: mutedOf(context, Colors.black54)),
                  ),
                ],
              ),
        onLongPress: m.isFinished ? () => startSelecting(m.idMeeting.toString()) : null,
        onTap: isSelecting
            ? () => toggleSelect(m.idMeeting.toString())
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MeetingDetailScreen(meeting: m),
                  ),
                );
                _load();
              },
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return "Aujourd'hui ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    }
    return "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }
}
