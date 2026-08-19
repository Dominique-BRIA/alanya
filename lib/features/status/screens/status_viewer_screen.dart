import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api_client.dart';
import '../../../core/token_storage.dart';
import '../../../models/status.dart';
import '../../../widgets/auth_network_image.dart';
import '../../../widgets/avatar_circle.dart';
import '../status_repository.dart';
import 'create_status_screen.dart' show colorFromHex;

/// Durée d'affichage d'un statut qui n'a pas de durée propre (texte, image).
const Duration _dureeFixe = Duration(seconds: 5);

/// Plafond de la barre de progression d'une vidéo.
///
/// La barre suit la durée RÉELLE de la vidéo, mais une vidéo anormalement
/// longue immobiliserait la visionneuse sans que rien ne la fasse avancer :
/// le plafond garantit qu'un statut finit toujours par céder la place.
const Duration _dureeVideoMax = Duration(seconds: 60);

/// Visionneuse plein écran des statuts, façon WhatsApp.
///
/// Elle reçoit **toute la liste** des personnes affichées et non une seule :
/// c'est ce qui permet d'enchaîner automatiquement sur la personne suivante
/// quand les statuts de la précédente sont épuisés, et de passer de l'une à
/// l'autre au doigt. Ouvrir « Mon statut » revient à lui passer une liste
/// d'un seul élément.
class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.groups,
    required this.isMine,
    this.initialGroup = 0,
  });

  final List<StatusGroup> groups;
  final bool isMine;
  final int initialGroup;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  late int _groupe = widget.initialGroup.clamp(0, widget.groups.length - 1);
  late final PageController _pages = PageController(initialPage: _groupe);

  String _baseUrl = "";
  String? _token;

  @override
  void initState() {
    super.initState();
    // Immersion : la visionneuse occupe l'écran entier, barres système
    // comprises. « sticky » les fait revenir d'un balayage puis disparaître
    // à nouveau, sans jamais reprendre la place réservée au contenu.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadConfig();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _pages.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final base = context.read<ApiClient>().baseUrl;
    final token = await context.read<TokenStorage>().accessToken;
    if (!mounted) return;
    setState(() {
      _baseUrl = base;
      _token = token;
    });
  }

  /// Passe à la personne suivante, ou referme s'il n'y en a plus.
  void _groupeSuivant() {
    if (_groupe < widget.groups.length - 1) {
      _pages.nextPage(
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Revient à la personne précédente. Rend `false` s'il n'y en a pas —
  /// la vue appelante relance alors la barre de son premier statut plutôt que
  /// de refermer, comme le fait WhatsApp.
  bool _groupePrecedent() {
    if (_groupe == 0) return false;
    _pages.previousPage(
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Balayage vers le bas = fermer. Le geste vertical ne dispute rien au
        // `PageView`, qui ne réclame que l'horizontal.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 250) Navigator.of(context).pop();
        },
        child: PageView.builder(
          controller: _pages,
          itemCount: widget.groups.length,
          onPageChanged: (i) => setState(() => _groupe = i),
          itemBuilder: (_, i) => _VueGroupe(
            key: ValueKey(widget.groups[i].userId),
            groupe: widget.groups[i],
            estMien: widget.isMine,
            actif: i == _groupe,
            baseUrl: _baseUrl,
            token: _token,
            onSuivant: _groupeSuivant,
            onPrecedent: _groupePrecedent,
          ),
        ),
      ),
    );
  }
}

/// Les statuts d'UNE personne : barres de progression, enchaînement, pause.
///
/// Cette vue n'est animée que lorsqu'elle est [actif]. Les pages voisines d'un
/// `PageView` sont construites d'avance : sans cette garde, les statuts des
/// deux personnes suivantes défileraient — et seraient marqués vus — pendant
/// qu'on regarde la première.
class _VueGroupe extends StatefulWidget {
  const _VueGroupe({
    super.key,
    required this.groupe,
    required this.estMien,
    required this.actif,
    required this.baseUrl,
    required this.token,
    required this.onSuivant,
    required this.onPrecedent,
  });

  final StatusGroup groupe;
  final bool estMien;
  final bool actif;
  final String baseUrl;
  final String? token;
  final VoidCallback onSuivant;
  final bool Function() onPrecedent;

  @override
  State<_VueGroupe> createState() => _VueGroupeState();
}

class _VueGroupeState extends State<_VueGroupe>
    with SingleTickerProviderStateMixin {
  late int _index = _premierNonVu();
  bool _enPause = false;

  /// Vrai tant que la vidéo courante n'a pas annoncé sa durée : la barre ne
  /// doit pas courir pendant le chargement, sinon un statut vidéo est passé
  /// avant d'avoir commencé sur une connexion lente.
  bool _attendVideo = false;

  late final AnimationController _progression = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _suivant();
    });

  int _premierNonVu() {
    final i = widget.groupe.statuses.indexWhere((s) => !s.viewed);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    if (widget.actif) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.actif) _entre();
      });
    }
  }

  @override
  void didUpdateWidget(_VueGroupe old) {
    super.didUpdateWidget(old);
    if (widget.actif == old.actif) return;
    if (widget.actif) {
      // On revient sur cette personne : on repart de son premier statut non vu.
      setState(() => _index = _premierNonVu());
      _entre();
    } else {
      _progression.stop();
    }
  }

  @override
  void dispose() {
    _progression.dispose();
    super.dispose();
  }

  void _entre() {
    _marqueVu();
    _demarreProgression();
  }

  StatusItem get _courant => widget.groupe.statuses[_index];

  /// (Re)lance la barre du statut courant. Une vidéo attend sa durée réelle.
  void _demarreProgression() {
    _progression.stop();
    if (_courant.type == "VIDEO") {
      setState(() => _attendVideo = true);
      _progression.value = 0;
      return;
    }
    _attendVideo = false;
    _progression.duration = _dureeFixe;
    _progression.forward(from: 0);
  }

  /// Appelé par le lecteur dès que la vidéo connaît sa durée.
  void _videoPrete(Duration duree) {
    if (!mounted || !_attendVideo) return;
    setState(() => _attendVideo = false);
    final d = duree > _dureeVideoMax || duree <= Duration.zero
        ? _dureeVideoMax
        : duree;
    _progression.duration = d;
    if (!_enPause) _progression.forward(from: 0);
  }

  /// Une vidéo illisible ne doit pas bloquer la personne suivante.
  void _videoEchouee() {
    if (!mounted || !_attendVideo) return;
    setState(() => _attendVideo = false);
    _progression.duration = _dureeFixe;
    if (!_enPause) _progression.forward(from: 0);
  }

  void _marqueVu() {
    if (widget.estMien) return;
    final s = _courant;
    if (!s.viewed) context.read<StatusRepository>().markViewed(s.id);
  }

  void _suivant() {
    if (!mounted) return;
    if (_index < widget.groupe.statuses.length - 1) {
      setState(() => _index++);
      _entre();
    } else {
      widget.onSuivant();
    }
  }

  void _precedent() {
    if (_index > 0) {
      setState(() => _index--);
      _entre();
      return;
    }
    // Premier statut de la personne : on remonte à la précédente si elle
    // existe, sinon on rejoue simplement la barre en cours.
    if (!widget.onPrecedent()) _demarreProgression();
  }

  void _pause(bool valeur) {
    if (_enPause == valeur) return;
    setState(() => _enPause = valeur);
    if (valeur) {
      _progression.stop();
    } else if (!_attendVideo) {
      _progression.forward();
    }
  }

  Future<void> _supprimer() async {
    final s = _courant;
    final repo = context.read<StatusRepository>();
    final nav = Navigator.of(context);
    _pause(true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ce statut ?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Supprimer")),
        ],
      ),
    );
    if (ok != true) {
      _pause(false);
      return;
    }
    try {
      await repo.delete(s.id);
    } catch (_) {
      // ignoré : la liste sera rechargée à la fermeture de toute façon.
    }
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groupe.statuses.isEmpty) return const SizedBox.shrink();
    final s = _courant;
    final bg = s.bgColor != null ? colorFromHex(s.bgColor!) : Colors.black;
    return Container(
      color: bg,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.localPosition.dx < w / 3) {
            _precedent();
          } else {
            _suivant();
          }
        },
        // Maintenir le doigt met en pause, façon WhatsApp : la barre s'arrête
        // et la vidéo aussi, jusqu'au relâchement.
        onLongPressStart: (_) => _pause(true),
        onLongPressEnd: (_) => _pause(false),
        onLongPressCancel: () => _pause(false),
        child: SafeArea(
          child: Column(
            children: [
              _barres(),
              _entete(s),
              Expanded(child: Center(child: _contenu(s))),
              if (widget.estMien) _pieVues(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barres() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: AnimatedBuilder(
        animation: _progression,
        builder: (_, __) => Row(
          children: List.generate(widget.groupe.statuses.length, (i) {
            final double fill =
                i < _index ? 1.0 : (i == _index ? _progression.value : 0.0);
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
    );
  }

  Widget _entete(StatusItem s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          AvatarCircle(
            name: widget.groupe.displayName,
            avatarUrl: widget.groupe.avatarUrl,
            radius: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.groupe.displayName,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                Text(_ago(s.createdAt),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          if (widget.estMien)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _supprimer,
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _contenu(StatusItem s) {
    if (s.type == "TEXT") {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          s.text ?? "",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (widget.token == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    if (s.type == "IMAGE" && s.mediaUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AuthNetworkImage(
          url: "${widget.baseUrl}${s.mediaUrl}",
          token: widget.token,
          fit: BoxFit.contain,
        ),
      );
    }
    if (s.type == "VIDEO" && s.mediaUrl != null) {
      return _StatusVideoPlayer(
        key: ValueKey(s.id),
        url: "${widget.baseUrl}${s.mediaUrl}?token=${widget.token ?? ''}",
        enPause: _enPause,
        onPret: _videoPrete,
        onEchec: _videoEchouee,
      );
    }
    return const Text(
      "[Média non pris en charge]",
      style: TextStyle(color: Colors.white70),
    );
  }

  Widget _pieVues(StatusItem s) {
    return GestureDetector(
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
    );
  }

  // Feuille « Vu par » : liste des personnes ayant vu mon statut + horodatage.
  Future<void> _showViewers(String statusId) async {
    final repo = context.read<StatusRepository>();
    _pause(true);
    await showModalBottomSheet<void>(
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
    if (mounted) _pause(false);
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
    final sameDay = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
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

/// Lecteur vidéo d'un statut.
///
/// Il ne boucle PAS : dans une visionneuse, la fin de la vidéo doit céder la
/// place au statut suivant. Il annonce sa durée à la vue parente, qui règle
/// dessus la barre de progression — sans quoi la barre et l'image ne parlent
/// pas du même temps.
class _StatusVideoPlayer extends StatefulWidget {
  const _StatusVideoPlayer({
    super.key,
    required this.url,
    required this.enPause,
    required this.onPret,
    required this.onEchec,
  });

  final String url;
  final bool enPause;
  final void Function(Duration duree) onPret;
  final VoidCallback onEchec;

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
      if (!widget.enPause) c.play();
      setState(() {});
      widget.onPret(c.value.duration);
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _error = true);
      widget.onEchec();
    });
  }

  @override
  void didUpdateWidget(_StatusVideoPlayer old) {
    super.didUpdateWidget(old);
    if (widget.enPause == old.enPause) return;
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (widget.enPause) {
      c.pause();
    } else {
      c.play();
    }
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
