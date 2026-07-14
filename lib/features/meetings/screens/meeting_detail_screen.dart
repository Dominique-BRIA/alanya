import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../../models/meeting.dart';
import '../../auth/auth_controller.dart';
import '../meetings_repository.dart';

/// Écran de détail d'une réunion — affiche les participants, permet
/// de rejoindre, quitter ou terminer la réunion.
class MeetingDetailScreen extends StatefulWidget {
  const MeetingDetailScreen({super.key, required this.meeting});
  final Meeting meeting;

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  late Meeting _meeting;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _meeting = widget.meeting;
  }

  bool get _isOrganiser {
    final myId = context.read<AuthController>().user?.id;
    return _meeting.organiser.id == myId;
  }

  bool get _amConnected {
    final myId = context.read<AuthController>().user?.id;
    return _meeting.participants.any((p) => p.userId == myId && p.isConnected);
  }

  Future<void> _refresh() async {
    try {
      final updated =
          await context.read<MeetingsRepository>().fetchMeeting(_meeting.idMeeting);
      if (mounted) setState(() => _meeting = updated);
    } catch (_) {}
  }

  Future<void> _join() async {
    setState(() => _loading = true);
    try {
      await context.read<MeetingsRepository>().joinMeeting(_meeting.idMeeting);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Connecté à la réunion")),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _loading = true);
    try {
      await context.read<MeetingsRepository>().leaveMeeting(_meeting.idMeeting);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Vous avez quitté la réunion")),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _end() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Terminer la réunion ?"),
        content: const Text("Tous les participants seront déconnectés."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Terminer",
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await context.read<MeetingsRepository>().endMeeting(_meeting.idMeeting);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Réunion terminée")),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _meeting;
    final typeLabel = m.isVideo ? "Vidéo" : "Audio";
    final statusLabel = m.isFinished ? "Terminée" : "En cours";

    return Scaffold(
      appBar: backAppBar(context, "Réunion"),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- Carte principale ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AlanyaColors.sand),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          m.isVideo ? Icons.videocam : Icons.call,
                          color: m.isFinished ? Colors.grey : AlanyaColors.forest,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            m.objet,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _infoRow("Type", typeLabel),
                    _infoRow("Statut", statusLabel),
                    _infoRow("Salle", m.room),
                    _infoRow("Durée prévue",
                        _formatDuration(m.duree)),
                    _infoRow("Début", _formatDateTime(m.startTime)),
                    _infoRow("Organisateur",
                        m.organiser.displayName),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Boutons d'action ---
              if (!m.isFinished) ...[
                if (!_amConnected)
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _join,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.login),
                    label: const Text("Rejoindre la réunion"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AlanyaColors.forest,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _leave,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text("Quitter la réunion",
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                if (_isOrganiser) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _end,
                    icon: const Icon(Icons.stop_circle_outlined,
                        color: Colors.red),
                    label: const Text("Terminer la réunion",
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),

              // --- Liste des participants ---
              Text(
                "Participants (${m.participants.length})",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...m.participants.map(_participantTile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child:
                Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _participantTile(MeetingParticipant p) {
    final statusText = p.isConnected
        ? "Connecté"
        : p.status == 1
            ? "Accepté"
            : p.status == 2
                ? "Décliné"
                : "Invité";

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: AvatarCircle(
          name: p.displayName,
          avatarUrl: p.avatarUrl,
          radius: 20,
          backgroundColor: AlanyaColors.clay,
        ),
        title: Text(p.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(statusText, style: const TextStyle(fontSize: 12)),
        trailing: p.duree != null
            ? Text(_formatDuration(p.duree!),
                style: const TextStyle(fontSize: 12, color: Colors.black54))
            : null,
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return "${h}h${m.toString().padLeft(2, '0')}";
    return "${m}min";
  }

  String _formatDateTime(DateTime d) {
    return "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }
}
