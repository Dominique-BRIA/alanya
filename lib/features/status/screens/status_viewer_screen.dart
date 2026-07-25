import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api_client.dart';
import '../../../core/token_storage.dart';
import '../../../models/status.dart';
import '../../../widgets/auth_network_image.dart';
import '../../../widgets/avatar_circle.dart';
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

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  String _baseUrl = "";
  String? _token;

  late final AnimationController _progress = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });

  Duration _durationFor(int index) {
    final s = widget.group.statuses[index];
    // Vidéo : un peu plus long ; texte/image : 5 s (comme WhatsApp).
    return Duration(seconds: s.type == "VIDEO" ? 20 : 5);
  }

  void _startProgress() {
    _progress.stop();
    _progress.duration = _durationFor(_index);
    _progress.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _markViewed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startProgress();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
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
    if (!mounted) return;
    if (_index < widget.group.statuses.length - 1) {
      setState(() => _index++);
      _markViewed();
      _startProgress();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _startProgress();
    } else {
      _startProgress(); // relance la barre du 1er statut
    }
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
              // Barres de progression animées (façon WhatsApp).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (_, __) => Row(
                    children: List.generate(widget.group.statuses.length, (i) {
                      final double fill = i < _index
                          ? 1.0
                          : (i == _index ? _progress.value : 0.0);
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: fill,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
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
                                ? (_token == null
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : _StatusVideoPlayer(
                                        key: ValueKey(s.id),
                                        url: _mediaUrl(s.mediaUrl!)))
                                : const Text(
                                    "[Média non pris en charge]",
                                    style: TextStyle(color: Colors.white70),
                                  ),
                  ),
                ),
              ),
              if (widget.isMine)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showViewers(s.id),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.visibility, color: Colors.white70, size: 18),
                        const SizedBox(width: 6),
                        Text("${s.viewsCount} vue(s)",
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_up,
                            color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Feuille « Vu par » : liste des personnes ayant vu mon statut + horodatage.
  void _showViewers(String statusId) {
    final repo = context.read<StatusRepository>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.getViews(statusId),
        builder: (fctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 160, child: Center(child: CircularProgressIndicator()));
          }
          final views = snap.data ?? const [];
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.visibility, size: 18),
                  const SizedBox(width: 8),
                  Text("Vu par ${views.length}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ),
              const Divider(height: 1),
              if (views.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("Personne n'a encore vu ce statut.")),
              ...views.map((v) {
                final viewedStr = v["viewedAt"] as String?;
                final when = viewedStr != null
                    ? _viewedLabel(DateTime.tryParse(viewedStr))
                    : "";
                return ListTile(
                  leading: AvatarCircle(
                      name: v["name"] as String?,
                      avatarUrl: v["avatarUrl"] as String?,
                      radius: 18),
                  title: Text((v["name"] as String?) ?? ""),
                  trailing: Text(when,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                );
              }),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  /// Horodatage de visionnage : « maintenant », « il y a N min », « à 12h50 »
  /// (aujourd'hui) ou « le JJ/MM à 12h50 ».
  String _viewedLabel(DateTime? d) {
    if (d == null) return "";
    final local = d.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inSeconds < 60) return "maintenant";
    if (diff.inMinutes < 60) return "il y a ${diff.inMinutes} min";
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final sameDay =
        now.year == local.year && now.month == local.month && now.day == local.day;
    if (sameDay) return "à ${hh}h$mm";
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return "le $dd/$mo à ${hh}h$mm";
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return "il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "il y a ${diff.inHours} h";
    return "il y a ${diff.inDays} j";
  }
}

/// Lecteur vidéo intégré pour les statuts (autoplay en boucle).
class _StatusVideoPlayer extends StatefulWidget {
  const _StatusVideoPlayer({super.key, required this.url});
  final String url;

  @override
  State<_StatusVideoPlayer> createState() => _StatusVideoPlayerState();
}

class _StatusVideoPlayerState extends State<_StatusVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ctrl = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      c.play();
      setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Text("Vidéo indisponible",
          style: TextStyle(color: Colors.white70));
    }
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }
}
