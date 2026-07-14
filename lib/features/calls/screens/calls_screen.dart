import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/call_cache.dart';
import '../../../models/call_record.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/motif_background.dart';
import '../call_controller.dart';
import '../calls_repository.dart';
import '../../chat/screens/chat_screen.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
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
    // 1) Cache local d'abord (offline-first).
    final cached = await CallCache.getAll();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _calls = cached;
        _error = false;
      });
    }
    // 2) Rafraîchit depuis le serveur.
    try {
      final calls = await context.read<CallsRepository>().history();
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _error = false;
      });
      await CallCache.putAll(calls);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _calls == null || _calls!.isEmpty);
      }
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case "RINGING":
        return "Sonnerie";
      case "ONGOING":
        return "En cours";
      case "ENDED":
        return "Terminé";
      case "MISSED":
        return "Manqué";
      case "REJECTED":
        return "Refusé";
      default:
        return s;
    }
  }

  String _duration(CallRecord c) {
    if (c.durationSec != null && c.durationSec! > 0) {
      final m = c.durationSec! ~/ 60;
      final s = c.durationSec! % 60;
      return "${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}";
    }
    return _statusLabel(c.status);
  }

  @override
  Widget build(BuildContext context) {
    return MotifBackground(
      overlayOpacity: 0.92,
      child: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_calls == null && !_error) {
      return ListView(children: const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: AppColors.terracotta)),
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
      return ListView(children: const [
        SizedBox(height: 100),
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Aucun appel pour le moment.\nLance un appel depuis une discussion (icône 📞).",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
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
    final isVideo = c.type == "VIDEO";
    final icon = c.isOutgoing
        ? Icons.call_made
        : (c.status == "MISSED" ? Icons.call_missed : Icons.call_received);
    final color = c.status == "MISSED" ? Colors.red : AppColors.forest;
    return ListTile(
      leading: c.isGroup
          ? CircleAvatar(
              backgroundColor: AppColors.clay,
              child: const Icon(Icons.groups, color: Colors.white, size: 20),
            )
          : AvatarCircle(
              name: c.peerName,
              avatarUrl: c.peerAvatarUrl,
              radius: 22,
              backgroundColor: AppColors.clay,
            ),
      title: Text(c.peerName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        "${c.isGroup ? "Groupe · " : ""}${c.isOutgoing ? "Sortant" : "Entrant"} · ${_duration(c)}",
        style: TextStyle(color: c.status == "MISSED" ? Colors.red.shade700 : Colors.black54),
      ),
      trailing: Icon(icon, color: color, size: 20),
      onTap: c.convId == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    convId: c.convId!,
                    title: c.peerName,
                    isGroup: c.isGroup,
                  ),
                ),
              ),
    );
  }
}
