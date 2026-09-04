import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api_client.dart';
import '../../../core/media_cache.dart';
import '../../../core/token_storage.dart';
import '../../../models/status.dart';
import '../../../widgets/auth_network_image.dart';
import '../../../widgets/avatar_circle.dart';
import '../../chat/chat_repository.dart';
import '../gestes_visionneuse.dart';
import '../horodatage_statut.dart';
import '../status_repository.dart';
import 'create_status_screen.dart' show colorFromHex;

/// Durée d'affichage d'un statut qui n'a pas de durée propre (texte, image).
const Duration _dureeFixe = Duration(seconds: 5);

/// Plafond de la barre de progression d'une vidéo.
///
/// La barre suit la durée RÉELLE de la vidéo, mais une vidéo anormalement
/// longue immobiliserait la visionneuse sans que rien ne la fasse avancer :
/// le plafond garantit qu'un statut finit toujours par céder la place.
///
/// ⚠️ PUBLIC PARCE QUE L'ÉCRAN DE PUBLICATION S'EN SERT AUSSI : il refuse une
/// vidéo plus longue, qui serait de toute façon coupée ici après avoir été
/// téléversée en entier. Les deux doivent parler de la même limite.
const Duration dureeVideoStatutMax = Duration(seconds: 60);

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

/// Ce qui empêche la barre d'avancer.
///
/// 🔴 UN ENSEMBLE, ET NON DES BOOLÉENS INDÉPENDANTS. Il suffit qu'UNE raison
/// subsiste pour rester en pause. Avec deux drapeaux séparés, un doigt posé
/// pendant le téléchargement d'une image relançait la barre au relâchement
/// alors que l'image n'était toujours pas arrivée.
enum _RaisonPause {
  /// Le doigt est posé sur l'écran.
  doigt,

  /// Le média du statut courant n'est pas encore affichable.
  chargement,

  /// Une boîte de dialogue ou une feuille est ouverte par-dessus.
  dialogue,
}

class _VueGroupeState extends State<_VueGroupe>
    with SingleTickerProviderStateMixin {
  late int _index = _premierNonVu();

  final Set<_RaisonPause> _pauses = {};

  /// Le champ « Répondre… » sous le statut de quelqu'un d'autre.
  final TextEditingController _reponseCtrl = TextEditingController();
  bool _envoiReponse = false;
  bool get _enPause => _pauses.isNotEmpty;

  /// Instant où le doigt s'est posé. Sert à départager, au relâchement, le tap
  /// (qui change de statut) du maintien (qui reprend sur place).
  DateTime? _debutAppui;

  /// Au-delà, on cesse d'attendre le média et la barre repart.
  ///
  /// Sans ce plafond, un média qui n'arrive jamais — jeton absent, réseau
  /// coupé, fichier manquant côté serveur — figerait la visionneuse sur un
  /// écran noir que rien ne fait avancer tout seul. Même famille que le
  /// plafond de 60 s d'une vidéo.
  static const Duration _attenteMediaMax = Duration(seconds: 15);
  Timer? _minuteurChargement;

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
      // On revient sur cette personne : on repart de son premier statut non vu,
      // et d'aucune pause héritée — le doigt qui a fait glisser la page ne
      // s'est pas relevé sur CETTE vue.
      setState(() {
        _index = _premierNonVu();
        _pauses.clear();
        _debutAppui = null;
      });
      _entre();
    } else {
      _minuteurChargement?.cancel();
      _progression.stop();
    }
  }

  @override
  void dispose() {
    _minuteurChargement?.cancel();
    _progression.dispose();
    _reponseCtrl.dispose();
    super.dispose();
  }

  void _entre() {
    _marqueVu();
    _demarreProgression();
  }

  StatusItem get _courant => widget.groupe.statuses[_index];

  /// (Re)lance la barre du statut courant.
  ///
  /// ⚠️ UN MÉDIA DOIT ÊTRE LÀ AVANT QUE SA BARRE NE COURE. C'est la barre qui
  /// décide du temps d'affichage, jamais le réseau : sans cette attente, une
  /// photo ou une vidéo lente est passée avant d'être apparue. L'attente vaut
  /// désormais pour l'IMAGE aussi, et non plus pour la seule vidéo.
  void _demarreProgression() {
    _minuteurChargement?.cancel();
    _progression.stop();
    _progression.value = 0;
    // Durée par défaut ; une vidéo la remplacera par la sienne.
    _progression.duration = _dureeFixe;

    if (_courant.type == "TEXT") {
      _pauses.remove(_RaisonPause.chargement);
    } else {
      _pauses.add(_RaisonPause.chargement);
      _minuteurChargement = Timer(_attenteMediaMax, _mediaEchoue);
    }
    if (mounted) setState(() {});
    if (!_enPause) _progression.forward(from: 0);
  }

  /// Le média du statut courant est affichable : la barre peut partir.
  ///
  /// [duree] n'est renseignée que par une vidéo — c'est elle qui règle alors la
  /// barre, plafonnée. Une image garde la durée fixe.
  void _mediaPret({Duration? duree}) {
    if (!mounted || !_pauses.contains(_RaisonPause.chargement)) return;
    _minuteurChargement?.cancel();
    if (duree != null) {
      _progression.duration = duree > dureeVideoStatutMax || duree <= Duration.zero
          ? dureeVideoStatutMax
          : duree;
    }
    _retirePause(_RaisonPause.chargement);
  }

  /// Un média illisible ne doit pas bloquer la personne suivante : la barre
  /// repart sur la durée fixe et le statut cède la place comme les autres.
  void _mediaEchoue() => _mediaPret();

  void _ajoutePause(_RaisonPause raison) {
    if (!_pauses.add(raison)) return;
    _progression.stop();
    if (mounted) setState(() {});
  }

  void _retirePause(_RaisonPause raison) {
    if (!_pauses.remove(raison)) return;
    if (mounted) setState(() {});
    // On ne repart que si PLUS AUCUNE raison ne subsiste.
    if (_pauses.isEmpty) _progression.forward();
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

  // ── Gestes ────────────────────────────────────────────────────────────────

  /// Le doigt vient de se poser : le défilement s'arrête immédiatement.
  void _appuiDebut() {
    _debutAppui = DateTime.now();
    _ajoutePause(_RaisonPause.doigt);
  }

  /// Le doigt se lève. Un appui COURT change de statut ; un maintien reprend
  /// simplement la lecture là où elle s'était arrêtée.
  void _appuiFin(double dx) {
    final debut = _debutAppui;
    _debutAppui = null;
    final duree =
        debut == null ? Duration.zero : DateTime.now().difference(debut);

    if (estAppuiCourt(duree)) {
      // On quitte ce statut : inutile de relancer sa barre, celle du suivant
      // repartira de zéro. La pause est donc retirée sans reprise.
      _pauses.remove(_RaisonPause.doigt);
      if (zonePrecedente(dx, MediaQuery.of(context).size.width)) {
        _precedent();
      } else {
        _suivant();
      }
      return;
    }
    _retirePause(_RaisonPause.doigt);
  }

  /// Le geste a été repris par un autre — balayage entre personnes, ou
  /// fermeture : on reprend la lecture sans changer de statut.
  void _appuiAnnule() {
    _debutAppui = null;
    _retirePause(_RaisonPause.doigt);
  }

  Future<void> _supprimer() async {
    final s = _courant;
    final repo = context.read<StatusRepository>();
    final nav = Navigator.of(context);
    _ajoutePause(_RaisonPause.dialogue);
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
      _retirePause(_RaisonPause.dialogue);
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
        /*
         * 🔴 PAUSE DÈS QUE LE DOIGT TOUCHE, ET NON APRÈS UN APPUI LONG.
         *
         * L'appui long imposait de tenir 500 ms avant que quoi que ce soit ne
         * s'arrête, et un maintien plus court ne mettait jamais en pause. Sur
         * WhatsApp, poser le doigt arrête tout de suite ; c'est la DURÉE de
         * l'appui, mesurée au relâchement, qui dit s'il faut changer de statut.
         *
         * ⚠️ Il ne doit plus y avoir de reconnaisseur d'appui long ici : il
         * gagnerait l'arène au bout de 500 ms et annulerait le tap, si bien que
         * `onTapUp` ne serait jamais appelé sur un maintien — la lecture ne
         * repartirait plus au relâchement.
         */
        onTapDown: (_) => _appuiDebut(),
        onTapUp: (d) => _appuiFin(d.localPosition.dx),
        onTapCancel: _appuiAnnule,
        child: SafeArea(
          child: Column(
            children: [
              _barres(),
              _entete(s),
              Expanded(child: Center(child: _contenu(s))),
              // La légende d'un média. Un statut TEXTE, lui, EST son texte :
              // le répéter ici l'afficherait deux fois.
              if (s.type != "TEXT" && (s.text?.trim().isNotEmpty ?? false))
                _legende(s.text!),
              if (widget.estMien) _pieVues(s) else _barreReponse(),
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
                Text(horodatageStatut(s.createdAt),
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
          key: ValueKey(s.id),
          url: "${widget.baseUrl}${s.mediaUrl}",
          token: widget.token,
          fit: BoxFit.contain,
          // La barre attend la photo, exactement comme elle attend la vidéo.
          onCharge: _mediaPret,
          onEchec: _mediaEchoue,
        ),
      );
    }
    if (s.type == "VIDEO" && s.mediaUrl != null) {
      return _StatusVideoPlayer(
        key: ValueKey(s.id),
        url: "${widget.baseUrl}${s.mediaUrl}?token=${widget.token ?? ''}",
        mediaId: s.mediaUrl?.split("/").last,
        // ⚠️ SEUL LE DOIGT met la vidéo en pause. Lui repasser la raison
        // « chargement » l'empêcherait de démarrer : c'est le lecteur qui lève
        // cette raison-là, une fois qu'il connaît sa durée.
        enPause: _pauses.contains(_RaisonPause.doigt),
        onPret: (duree) => _mediaPret(duree: duree),
        onEchec: _mediaEchoue,
      );
    }
    return const Text(
      "[Média non pris en charge]",
      style: TextStyle(color: Colors.white70),
    );
  }

  /// Réactions rapides, comme WhatsApp.
  static const _reactions = ["❤️", "😂", "😮", "😢", "🙏", "👏", "🔥", "🎉"];

  /// Répondre à un statut, ou y réagir.
  ///
  /// 🔴 UNE RÉPONSE EST UN MESSAGE PRIVÉ, ET RIEN D'AUTRE — c'est ce que fait
  /// WhatsApp, et c'est ce qui permet de n'écrire AUCUN code serveur : la
  /// réponse emprunte la voie normale d'un message. Elle hérite donc de tout ce
  /// qui y est déjà branché — remise par WebSocket, notification push, refus si
  /// l'un a bloqué l'autre, historique. Une route dédiée aurait redemandé tout
  /// ça, et l'aurait redemandé de travers.
  ///
  /// ⚠️ UNE RÉACTION EST UNE RÉPONSE D'UN SEUL EMOJI. Les deux gestes
  /// aboutissent au même endroit, ce qui évite un second mécanisme à tenir.
  ///
  /// 🚫 LE STATUT N'EST PAS CITÉ dans la conversation : `Message.replyToId` ne
  /// pointe que vers un autre MESSAGE, jamais vers un statut. Citer demanderait
  /// une table de correspondance et une modification de l'écran de discussion.
  /// L'auteur reçoit donc un message normal.
  Future<void> _repondre(String texte) async {
    final t = texte.trim();
    if (t.isEmpty || _envoiReponse) return;
    setState(() => _envoiReponse = true);
    final statutId = _courant.id;
    final chat = context.read<ChatRepository>();
    final messenger = ScaffoldMessenger.of(context);
    // Même raison que pour une feuille : le statut ne doit pas défiler pendant
    // qu'on écrit ni pendant l'envoi.
    _ajoutePause(_RaisonPause.dialogue);
    try {
      final conv = await chat.getOrCreateDirectConversation(widget.groupe.userId);
      final convId = conv["id"] as String;
      // Le statut regardé au moment de l'envoi : c'est lui que la conversation
      // citera. On le lit AVANT l'await de l'envoi, la barre pouvant avoir
      // avancé entre-temps.
      await chat.sendText(convId, t, statutCite: statutId);
      _reponseCtrl.clear();
      messenger.showSnackBar(
        SnackBar(content: Text("Envoyé à ${widget.groupe.displayName}")),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Envoi impossible")),
      );
    } finally {
      if (mounted) {
        setState(() => _envoiReponse = false);
        _retirePause(_RaisonPause.dialogue);
      }
    }
  }

  Widget _barreReponse() {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _reactions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, i) => InkWell(
                onTap: _envoiReponse ? null : () => _repondre(_reactions[i]),
                borderRadius: BorderRadius.circular(21),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Center(
                    child: Text(_reactions[i],
                        style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _reponseCtrl,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  // Le doigt dans le champ ne doit pas faire défiler le statut
                  // ni le mettre en pause : la saisie a sa propre vie.
                  onTap: () => _ajoutePause(_RaisonPause.dialogue),
                  onSubmitted: _repondre,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    counterText: "",
                    hintText: "Répondre…",
                    hintStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _envoiReponse
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, color: Colors.white),
                onPressed: _envoiReponse
                    ? null
                    : () => _repondre(_reponseCtrl.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// La légende posée sous une photo ou une vidéo.
  ///
  /// Défilante et bornée en hauteur : une légende de 700 caractères — le
  /// maximum accepté — chasserait sinon l'image hors de l'écran.
  Widget _legende(String texte) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 140),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: SingleChildScrollView(
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
          ),
        ),
      ),
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
    _ajoutePause(_RaisonPause.dialogue);
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
    if (mounted) _retirePause(_RaisonPause.dialogue);
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
    required this.mediaId,
    required this.enPause,
    required this.onPret,
    required this.onEchec,
  });

  final String url;

  /// L'identifiant du média, qui est AUSSI sa clé de cache disque : pour
  /// `/api/media/<id>`, `CachedMedia.cacheKey` rend le dernier segment.
  final String? mediaId;
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
    _demarrer();
  }

  /// Lit la vidéo DEPUIS LE CACHE quand elle y est, du réseau sinon.
  ///
  /// 🔴 UNE VIDÉO DE STATUT N'ÉTAIT JAMAIS MISE EN CACHE (signalé sur device le
  /// 04/09/2026) : `VideoPlayerController.networkUrl` retélécharge à chaque
  /// ouverture, y compris SA PROPRE vidéo qu'on vient de publier depuis ce
  /// téléphone. Les images passaient déjà par le cache disque ; les vidéos, qui
  /// pèsent cent fois plus, non.
  ///
  /// ⚠️ LE FICHIER EST ÉCRIT SANS EXTENSION UTILE (`.dat`, comme le reste du
  /// cache). ExoPlayer reconnaît le conteneur à son contenu, pas à son nom —
  /// mais si un jour une plateforme s'y refusait, le repli réseau ci-dessous
  /// resterait le chemin sûr.
  Future<void> _demarrer() async {
    VideoPlayerController c;
    final cache = widget.mediaId == null
        ? null
        : await MediaCache.get(widget.mediaId!, 'dat');
    if (!mounted) return;
    if (cache != null) {
      c = VideoPlayerController.file(File(cache));
    } else {
      c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    }
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
