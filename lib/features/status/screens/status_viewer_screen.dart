import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/token_storage.dart';
import '../../../models/status.dart';
import '../../../widgets/auth_network_image.dart';
import '../status_repository.dart';
import 'create_status_screen.dart' show colorFromHex;

/// Visionneuse plein écran des statuts d'un utilisateur (tap pour avancer).
class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({super.key, required this.group, required this.isMine});
  final StatusGroup group;
  final bool isMine;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  int _index = 0;
  String _baseUrl = "";
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _markViewed();
  }

  Future<void> _loadConfig() async {
    _baseUrl = context.read<ApiClient>().baseUrl;
    _token = await context.read<TokenStorage>().accessToken;
    if (mounted) setState(() {});
  }

  /// Construit l'URL complète d'un média de statut (avec token d'authentification).
  String _mediaUrl(String path) {
    return "$_baseUrl$path?token=${_token ?? ''}";
  }

  void _markViewed() {
    if (widget.isMine) return;
    final s = widget.group.statuses[_index];
    if (!s.viewed) {
      context.read<StatusRepository>().markViewed(s.id);
    }
  }

  void _next() {
    if (_index < widget.group.statuses.length - 1) {
      setState(() => _index++);
      _markViewed();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _delete() async {
    final s = widget.group.statuses[_index];
    final repo = context.read<StatusRepository>();
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Supprimer ce statut ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Supprimer")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.delete(s.id);
    } catch (_) {
      // ignoré
    }
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.group.statuses[_index];
    final bg = s.bgColor != null ? colorFromHex(s.bgColor!) : Colors.black;
    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.localPosition.dx < w / 3) {
            _prev();
          } else {
            _next();
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              // Barres de progression par statut.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: List.generate(widget.group.statuses.length, (i) {
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _index ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Text(
                        widget.group.displayName[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.group.displayName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text(_ago(s.createdAt),
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (widget.isMine)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white),
                        onPressed: _delete,
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: s.type == "TEXT"
                        ? Text(
                            s.text ?? "",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : s.type == "IMAGE" && s.mediaUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: _token == null
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : AuthNetworkImage(
                                        url: "$_baseUrl${s.mediaUrl}",
                                        token: _token,
                                        fit: BoxFit.contain,
                                      ),
                              )
                            : s.type == "VIDEO" && s.mediaUrl != null
                                ? _videoPlaceholder(s.mediaUrl!)
                                : const Text(
                                    "[Média non pris en charge]",
                                    style: TextStyle(color: Colors.white70),
                                  ),
                  ),
                ),
              ),
              if (widget.isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility, color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text("${s.viewsCount} vue(s)",
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Placeholder pour la vidéo — l'app ouvre le lecteur système au tap.
  /// (La lecture vidéo intégrée nécessiterait une dépendance supplémentaire ;
  /// pour l'instant on propose un bouton de téléchargement/ouverture.)
  Widget _videoPlaceholder(String mediaUrl) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
        const SizedBox(height: 12),
        const Text(
          "Vidéo",
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return "il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "il y a ${diff.inHours} h";
    return "il y a ${diff.inDays} j";
  }
}
