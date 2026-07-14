import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/motif_background.dart';
import '../../../models/meeting.dart';
import '../meetings_repository.dart';
import 'create_meeting_screen.dart';
import 'meeting_detail_screen.dart';

/// Onglet "Réunions" intégré dans la barre de navigation du HomeScreen.
///
/// Affiche la liste des réunions à venir et passées, avec un FAB pour créer.
class MeetingsScreen extends StatefulWidget {
  const MeetingsScreen({super.key});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
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

  @override
  Widget build(BuildContext context) {
    return MotifBackground(
      overlayOpacity: 0.92,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: _buildList(),
          ),
          // FAB positionné en bas à droite
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              backgroundColor: AppColors.fabPrimary,
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
      return const Center(
        child: CircularProgressIndicator(color: AppColors.terracotta),
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
      return ListView(children: const [
        SizedBox(height: 100),
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_outlined, size: 64, color: AppColors.clay),
                SizedBox(height: 12),
                Text(
                  "Aucune réunion.\nAppuie sur + pour créer une réunion audio ou vidéo.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text("En cours / À venir",
                style: TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.bold)),
          ),
          ...active.map(_tile),
        ],
        if (ended.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text("Terminées",
                style: TextStyle(
                    color: Colors.black38, fontWeight: FontWeight.bold)),
          ),
          ...ended.map(_tile),
        ],
        // Espace en bas pour laisser de la place au FAB
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
        leading: CircleAvatar(
          backgroundColor:
              m.isFinished ? Colors.grey.shade300 : AppColors.forest,
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
        trailing: Text(
          "${m.participants.length} 👥",
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        onTap: () async {
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
