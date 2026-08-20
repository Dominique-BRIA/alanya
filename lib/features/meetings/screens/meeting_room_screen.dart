import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/ringtone_service.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../auth/auth_controller.dart';
import '../meeting_controller.dart';
import '../meetings_repository.dart';

/// Écran de réunion active — style Google Meet.
///
/// Affiche les flux vidéo/audio des participants, avec des contrôles pour
/// micro, caméra, haut-parleur et quitter. Le [MeetingController] est GLOBAL :
/// fermer cet écran (flèche de réduction ou retour système) ne quitte pas la
/// réunion, il la minimise — le bandeau global permet d'y revenir, et le
/// service de premier plan garde l'audio vivant en arrière-plan.
class MeetingRoomScreen extends StatefulWidget {
  const MeetingRoomScreen({
    super.key,
    required this.meetingId,
    required this.objet,
    required this.isVideo,
    this.plannedDurationSec = 0,
    this.organiserId,
  });

  final int meetingId;
  final String objet;
  final bool isVideo;

  /// Durée prévue de la réunion (0 = pas de limite). Alimente le minuteur.
  final int plannedDurationSec;

  /// Organisateur de la réunion : lui seul voit « Prolonger » quand le terme
  /// approche. Nul quand la salle est rouverte depuis le bandeau — le
  /// contrôleur a déjà l'information, et `join` ne refait alors rien.
  final String? organiserId;

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  bool _joining = true;
  bool _joinAsAudio = false;
  StreamSubscription<MeetingAlerte>? _alertesSub;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join({bool forceAudio = false}) async {
    final ctrl = context.read<MeetingController>();
    // Ne rejoint que si on n'est pas déjà dans cette réunion (réouverture via
    // le bandeau) : le flux et la maille sont déjà en place.
    if (ctrl.activeMeetingId == widget.meetingId && ctrl.isActive) {
      if (mounted) setState(() => _joining = false);
      return;
    }
    final wantVideo = widget.isVideo && !forceAudio;
    try {
      await ctrl.join(
        widget.meetingId,
        isVideo: wantVideo,
        objet: widget.objet,
        plannedDurationSec: widget.plannedDurationSec,
        organiserId: widget.organiserId,
      );
      if (mounted) setState(() => _joining = false);
    } on Exception {
      // Permission refusée en vidéo : proposer de basculer en audio.
      if (wantVideo && mounted && !_joinAsAudio) {
        _joinAsAudio = true;
        final retry = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Caméra indisponible"),
            content: const Text(
                "La caméra n'a pas pu être activée. Rejoindre la réunion en audio ?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Rejoindre en audio"),
              ),
            ],
          ),
        );
        if (retry == true) {
          await _join(forceAudio: true);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(wantVideo
                  ? "Impossible de rejoindre la réunion."
                  : "Impossible de rejoindre la réunion en audio.")),
        );
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La salle est affichée → masque le bandeau global. Posé en post-frame car
    // il peut être appelé plusieurs fois au fil des dépendances.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MeetingController>().setRoomVisible(true);
    });
    // Une seule souscription, même si les dépendances changent plusieurs fois.
    _alertesSub ??= context.read<MeetingController>().alertes.listen(_onAlerte);
  }

  /// Réagit au franchissement d'un seuil de la durée prévue : une tonalité et un
  /// bandeau, une seule fois — c'est le contrôleur qui garantit l'unicité.
  void _onAlerte(MeetingAlerte a) {
    if (!mounted) return;
    RingtoneService.instance.playAlerteReunion();
    final ctrl = context.read<MeetingController>();
    final organisateur = ctrl.jeSuisOrganisateur;
    final texte = a == MeetingAlerte.finProche
        ? "Il reste 2 minutes sur la durée prévue."
        : "La durée prévue de la réunion est atteinte.";
    final messenger = ScaffoldMessenger.of(context);
    // Le bandeau précédent n'a plus lieu d'être : « il reste 2 minutes » devient
    // faux à l'instant où le terme est atteint.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(texte),
        duration: const Duration(seconds: 10),
        backgroundColor:
            a == MeetingAlerte.depassement ? AlanyaColors.terracotta : null,
        action: organisateur
            ? SnackBarAction(
                label: "Prolonger",
                textColor: Colors.white,
                onPressed: () {
                  ctrl.prolonger();
                  // Aucun retour optimiste : la confirmation arrive par
                  // `meeting_extended`, et l'en-tête repasse alors au vert.
                },
              )
            : SnackBarAction(
                label: "Ignorer",
                textColor: Colors.white,
                onPressed: messenger.hideCurrentSnackBar,
              ),
      ),
    );
  }

  /// Ajoute des participants sans quitter la salle (organisateur seulement).
  ///
  /// Les personnes déjà présentes sont retirées de la liste proposée. La salle
  /// ne connaît que les participants CONNECTÉS — un invité qui n'a pas encore
  /// rejoint n'en fait pas partie — donc le serveur reste seul juge : il écarte
  /// sans erreur ceux qui sont déjà membres, et c'est son décompte qui est
  /// annoncé.
  Future<void> _ajouterParticipants() async {
    final ctrl = context.read<MeetingController>();
    if (!ctrl.jeSuisOrganisateur) return;

    final numeros = await ContactPickerSheet.show(
      context,
      title: "Ajouter à la réunion",
      confirmLabel: "Ajouter",
    );
    if (numeros == null || numeros.isEmpty || !mounted) return;

    try {
      final ajoutes = await context
          .read<MeetingsRepository>()
          .addParticipants(widget.meetingId, numeros);
      if (!mounted) return;
      showAppSnackBar(
        ajoutes == 0
            ? "Ces contacts sont déjà dans la réunion"
            : ajoutes == 1
                ? "1 participant ajouté et prévenu"
                : "$ajoutes participants ajoutés et prévenus",
      );
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(e.message);
    }
  }

  /// Un participant PROPOSE quelqu'un à l'organisateur, sans quitter la salle.
  ///
  /// ⚠️ L'intéressé n'est prévenu de rien tant que l'organisateur n'a pas
  /// accepté. Le message le dit, sans quoi le demandeur croirait avoir invité
  /// quelqu'un et s'étonnerait de ne pas le voir arriver.
  Future<void> _proposerParticipant() async {
    final numeros = await ContactPickerSheet.show(
      context,
      title: "Proposer à l'organisateur",
      confirmLabel: "Proposer",
    );
    if (numeros == null || numeros.isEmpty || !mounted) return;

    try {
      await context
          .read<MeetingsRepository>()
          .requestInvite(widget.meetingId, numeros.first);
      if (mounted) {
        showAppSnackBar(
            "Demande envoyée. La personne n'est prévenue que si l'organisateur accepte.");
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(e.message);
    }
  }

  /// Réduit la salle SANS quitter : la réunion continue, le bandeau prend le
  /// relais. C'est le geste de retour système comme du bouton dédié.
  void _minimize() {
    Navigator.of(context).maybePop();
  }

  Future<void> _leave() async {
    final ctrl = context.read<MeetingController>();
    await ctrl.leave();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _alertesSub?.cancel();
    // L'écran disparaît : le bandeau global reprend si la réunion continue.
    // On ne quitte PAS la réunion ici — c'est le rôle du bouton rouge.
    context.read<MeetingController>().setRoomVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      // Le retour système RÉDUIT la réunion, il ne la quitte pas : l'audio doit
      // continuer. Pour raccrocher, le bouton rouge reste le geste explicite.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          context.read<MeetingController>().setRoomVisible(false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SafeArea(
          child: _joining
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text("Connexion en cours...",
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildHeader(),
                    _buildMainsLevees(),
                    Expanded(child: _buildVideoGrid()),
                    _buildControls(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            tooltip: "Réduire",
            onPressed: _minimize,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.objet,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                ListenableBuilder(
                  listenable: context.read<MeetingController>(),
                  builder: (_, __) {
                    final ctrl = context.read<MeetingController>();
                    return Text(
                      _subtitle(ctrl),
                      style: TextStyle(
                        color: _subtitleColor(ctrl),
                        fontSize: 12,
                        // Le gras n'arrive qu'avec la couleur : en régime
                        // normal, ce sous-titre ne doit pas tirer l'œil.
                        fontWeight: _subtitleColor(ctrl) == Colors.white54
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Bouton participants
          IconButton(
            icon: const Icon(Icons.people_outline, color: Colors.white),
            onPressed: _showParticipants,
          ),
          // Bouton chat
          ListenableBuilder(
            listenable: context.read<MeetingController>(),
            builder: (_, __) {
              final ctrl = context.read<MeetingController>();
              final unread = ctrl.unreadChatCount;
              return IconButton(
                tooltip: "Chat",
                onPressed: _showChat,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.white),
                    if (unread > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            unread > 9 ? "9+" : "$unread",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Sous-titre d'en-tête : minuteur de participation une fois le flux local
  /// prêt, sinon nombre de participants. Le compteur retenu est
  /// [MeetingController.participantCount] (participants annoncés par le
  /// serveur), pas le nombre de flux média connectés — un nouveau venu doit
  /// être compté tout de suite, pas seulement après sa négociation WebRTC.
  String _subtitle(MeetingController ctrl) {
    final depuis = ctrl.connectedSince;
    final compte = ctrl.participantCount;
    if (depuis != null) {
      final d = DateTime.now().difference(depuis);
      String two(int n) => n.toString().padLeft(2, '0');
      final t = d.inHours > 0
          ? "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}"
          : "${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
      // Temps restant si une durée prévue est définie.
      final duree = ctrl.plannedDurationSec;
      if (duree > 0) {
        final restant = duree - d.inSeconds;
        String fmt(int sec) {
          final m = sec ~/ 60;
          final s = sec % 60;
          return m >= 60
              ? "${m ~/ 60}:${two(m % 60)}:${two(s)}"
              : "$m:${two(s)}";
        }

        if (restant >= 0) {
          return "$compte · $t · ${fmt(restant)} restantes";
        }
        return "$compte · $t · +${fmt(-restant)} de dépassement";
      }
      return "$compte · $t";
    }
    return "$compte participant(s)";
  }

  /// Couleur du sous-titre : elle seule signale l'approche du terme sans qu'on
  /// ait à lire les chiffres. Orange dans les deux dernières minutes, rouge en
  /// dépassement, et retour au gris habituel dès qu'une prolongation redonne du
  /// temps — c'est le même calcul qui gouverne les trois états.
  Color _subtitleColor(MeetingController ctrl) {
    final restant = ctrl.secondesRestantes;
    if (restant == null) return Colors.white54;
    if (restant <= 0) return AlanyaColors.terracotta;
    if (restant <= MeetingController.seuilFinProcheSec) return Colors.orange;
    return Colors.white54;
  }

  /// Bandeau des mains levées : QUI demande la parole, en une ligne.
  ///
  /// Les pastilles posées sur les vignettes ne suffisent pas sur un téléphone :
  /// une main levée peut se trouver dans une case minuscule, dans la bande d'une
  /// présentation, ou hors de l'écran quand la grille défile. Cette ligne, elle,
  /// est toujours au même endroit et se lit d'un coup d'œil.
  ///
  /// Elle DISPARAÎT complètement dès qu'aucune main n'est levée : c'est ce qui
  /// permet de la mettre là sans encombrer. Un toucher ouvre la fiche des
  /// participants, où chaque main est de nouveau signalée nom par nom.
  Widget _buildMainsLevees() {
    return ListenableBuilder(
      listenable: context.read<MeetingController>(),
      builder: (_, __) {
        final ctrl = context.read<MeetingController>();
        // Les autres d'abord, moi en dernier : ce bandeau sert surtout à
        // repérer qui attend la parole, pas à se relire soi-même.
        final noms = <String>[
          for (final id in ctrl.peerIds)
            if (ctrl.isHandRaised(id))
              ctrl.participantNames[id] ?? "Participant",
          if (ctrl.myHandRaised) "Vous",
        ];
        if (noms.isEmpty) return const SizedBox.shrink();

        return GestureDetector(
          onTap: _showParticipants,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AlanyaColors.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.back_hand, color: AlanyaColors.gold, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _texteMainsLevees(noms, ctrl.myHandRaised),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AlanyaColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Phrase du bandeau des mains levées.
  ///
  /// Trois formes, et pas une de moins : au singulier la troisième personne
  /// (« Awa demande »), pour soi seul la deuxième (« Vous demandez »), et au
  /// pluriel un décompte suivi des noms — un verbe accordé sur une liste
  /// mêlant « Vous » et des tiers n'existe pas en français correct.
  String _texteMainsLevees(List<String> noms, bool laMienne) {
    if (noms.length == 1) {
      return laMienne
          ? "Vous demandez la parole"
          : "${noms.first} demande la parole";
    }
    return "${noms.length} mains levées · ${noms.join(', ')}";
  }

  /// Zone centrale : vignettes des participants.
  ///
  /// En RÉUNION AUDIO, on n'instancie AUCUN [RTCVideoRenderer] : le flux local
  /// ne contient qu'une piste audio, et créer des renderers vidéo réveillait la
  /// caméra sur certaines implémentations. On affiche à la place une liste
  /// d'avatars (le même style que la fiche participants). En vidéo, on rend les
  /// flux comme avant.
  Widget _buildVideoGrid() {
    return ListenableBuilder(
      listenable: context.read<MeetingController>(),
      builder: (_, __) {
        final ctrl = context.read<MeetingController>();

        if (!ctrl.activeIsVideo) {
          return _buildAudioGrid(ctrl);
        }

        // QUELQU'UN PRÉSENTE : son écran passe en grand tout seul, sans que
        // personne ait à le demander, et les autres se rangent dans une bande
        // dessous. C'est ce qu'on attend d'une réunion.
        //
        // ⚠️ Le présentateur est DÉSIGNÉ PAR LE SERVEUR (`meeting_screen`), il
        // n'est jamais deviné d'une piste vidéo : rien dans WebRTC ne distingue
        // un écran d'un visage, la piste emprunte le même tuyau que la caméra.
        // Sans cette annonce, un écran partagé arriverait ici comme une vignette
        // de plus, rognée pour remplir sa case.
        final presentateurId = ctrl.presentateurId;
        final fluxPresente =
            presentateurId != null ? ctrl.remoteStreams[presentateurId] : null;
        if (presentateurId != null && fluxPresente != null) {
          return _buildPresentation(ctrl, presentateurId, fluxPresente);
        }

        final remoteIds = ctrl.remoteStreams.keys.toList();
        final remoteCount = remoteIds.length;
        // Participants présents (source de vérité = liste des IDs connectés), y
        // compris ceux dont le flux n'est pas encore négocié : on leur réserve
        // une case avec un avatar en attendant.
        final pending = ctrl.peerIds
            .where((id) => !ctrl.remoteStreams.containsKey(id))
            .toList();
        final total = 1 + remoteCount + pending.length;

        if (total <= 1) {
          // Seul dans la réunion
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _localVideo(isLarge: true),
                const SizedBox(height: 16),
                const Text("En attente d'autres participants...",
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        if (total == 2 && remoteCount == 1) {
          // 1v1 : local en petit coin, remote en grand
          return Stack(
            children: [
              Positioned.fill(child: _remoteVideoSingle()),
              Positioned(
                right: 16,
                top: 16,
                width: 120,
                height: 160,
                child: _localVideo(isLarge: false),
              ),
            ],
          );
        }

        // Grille. Les tuiles sont ordonnées : soi, les flux distants, puis les
        // participants en attente de média (avatar).
        final cols = total <= 4 ? 2 : 3;
        final rows = (total / cols).ceil();
        final tiles = <Widget>[
          _localVideo(isLarge: false),
          ...remoteIds.map(_remoteVideoTile),
          ...pending.map((id) => _remoteVideoTile(id)),
        ];
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: rows == 1 ? 1.5 : 1.0,
          ),
          itemCount: tiles.length,
          itemBuilder: (_, i) => tiles[i],
        );
      },
    );
  }

  /// Disposition « quelqu'un présente » : l'écran en grand, les autres dessous.
  ///
  /// Le grand cadre est en `contain` et jamais en miroir — voir
  /// [RTCVideoRendererObject.estUnEcran], c'est là que se joue toute la
  /// différence avec un visage.
  ///
  /// Le présentateur ne se retrouve PAS dans la bande du bas : il est déjà en
  /// grand, sa vignette n'y ajouterait qu'un doublon plus petit. Ma propre image
  /// ouvre la bande, comme elle ouvre la grille ordinaire.
  Widget _buildPresentation(
    MeetingController ctrl,
    String presentateurId,
    MediaStream flux,
  ) {
    final nom = ctrl.participantNames[presentateurId] ?? "Participant";
    final autres = ctrl.peerIds.where((id) => id != presentateurId).toList();

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Fond NOIR sous l'écran : affiché en entier, il ne remplit
                  // pas la case et laisse deux bandes. Du noir franc les rend
                  // muettes ; le gris des vignettes vides, lui, ferait croire à
                  // un flux manquant.
                  const ColoredBox(color: Colors.black),
                  RTCVideoRendererObject(stream: flux, estUnEcran: true),
                  // CE QUI DIT « ÉCRAN » ET NON « CAMÉRA ». Sans cette
                  // étiquette, une présentation n'est qu'une image de plus, en
                  // plus grand : rien ne la distinguerait d'un gros plan.
                  Positioned(
                    left: 10,
                    bottom: 10,
                    right: 10,
                    child: Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.screen_share,
                                    color: AlanyaColors.gold, size: 14),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    "$nom · Écran partagé",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // La bande défile horizontalement plutôt que de se comprimer : sur un
        // téléphone, six vignettes réparties de force sur la largeur ne
        // montreraient plus personne.
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              SizedBox(
                width: 124,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _localVideo(isLarge: false),
                ),
              ),
              for (final id in autres)
                SizedBox(
                  width: 124,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _remoteVideoTile(id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Grille affichée en réunion AUDIO : avatars uniquement, pas de renderer.
  Widget _buildAudioGrid(MeetingController ctrl) {
    final me = context.read<AuthController>().user;
    // Moi + participants présents. On itère sur la liste des IDs connectés
    // (source de vérité), et non sur les clés des noms : un participant déjà
    // présent à notre arrivée n'a pas encore son nom résolu, il doit quand même
    // s'afficher (repli « Participant »).
    final entries = <({
      String id,
      String name,
      String? avatar,
      bool muted,
      bool hand,
      bool partage,
      bool me
    })>[
      (
        id: "me",
        name: me?.pseudo ?? "Vous",
        avatar: me?.avatarUrl,
        muted: ctrl.isMuted,
        hand: ctrl.myHandRaised,
        partage: false,
        me: true,
      ),
      for (final id in ctrl.peerIds)
        (
          id: id,
          name: ctrl.participantNames[id] ?? "Participant",
          avatar: ctrl.participantAvatars[id],
          muted: ctrl.isPeerMuted(id),
          hand: ctrl.isHandRaised(id),
          partage: ctrl.isSharingScreen(id),
          me: false,
        ),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 28,
          runSpacing: 28,
          alignment: WrapAlignment.center,
          children: entries.map((e) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarCircle(
                      name: e.name,
                      avatarUrl: e.avatar,
                      radius: 44,
                      backgroundColor:
                          e.me ? AlanyaColors.terracotta : AlanyaColors.forest,
                    ),
                    if (e.muted)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mic_off,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    if (e.hand)
                      Positioned(
                        left: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: AlanyaColors.gold,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.back_hand,
                              color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 96,
                  child: Text(
                    e.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                // Une MENTION et non une pastille : en réunion audio, aucune
                // piste vidéo n'est demandée au correspondant, l'écran partagé
                // ne nous parvient donc pas. On dit ce qui se passe plutôt que
                // de faire croire à une image qu'on pourrait ouvrir.
                if (e.partage)
                  const SizedBox(
                    width: 96,
                    child: Text(
                      "Partage son écran",
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AlanyaColors.gold, fontSize: 10),
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _localVideo({required bool isLarge}) {
    final ctrl = context.watch<MeetingController>();
    final stream = ctrl.localStream;
    final Widget child;
    if (stream == null || ctrl.isCameraOff) {
      child = _avatarPlaceholder(
        name: context.read<AuthController>().user?.pseudo ?? "Moi",
        isLarge: isLarge,
      );
    } else {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(isLarge ? 16 : 12),
        child: RTCVideoRendererObject(stream: stream),
      );
    }
    // Indicateur de main levée sur sa propre vignette (comme chez les pairs),
    // sinon en vidéo on ne voyait rien se passer quand on levait la main.
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (ctrl.myHandRaised)
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: AlanyaColors.gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.back_hand, color: Colors.white, size: 16),
            ),
          ),
      ],
    );
  }

  Widget _remoteVideoSingle() {
    final ctrl = context.watch<MeetingController>();
    final streams = ctrl.remoteStreams;
    if (streams.isEmpty) return const SizedBox.shrink();
    final entry = streams.entries.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: RTCVideoRendererObject(stream: entry.value),
    );
  }

  Widget _remoteVideoTile(String peerId) {
    final ctrl = context.watch<MeetingController>();
    final stream = ctrl.remoteStreams[peerId];
    final name = ctrl.participantNames[peerId] ?? "Participant";
    final avatarUrl = ctrl.participantAvatars[peerId];
    final muted = ctrl.isPeerMuted(peerId);
    final hand = ctrl.isHandRaised(peerId);
    // Le serveur accepte DEUX présentateurs à la fois et laisse le client
    // trancher : celui qui n'a pas le grand cadre garde sa vignette, mais son
    // écran y reste montré en entier, pas rogné comme un visage.
    final partage = ctrl.isSharingScreen(peerId);
    final hasVideo = stream != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo) ...[
            if (partage) const ColoredBox(color: Colors.black),
            RTCVideoRendererObject(stream: stream, estUnEcran: partage),
          ] else
            _avatarPlaceholder(
                name: name, isLarge: false, avatarUrl: avatarUrl),
          // Bandeau nom + état muet
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
                if (muted) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_off,
                        color: Colors.white, size: 14),
                  ),
                ],
                if (hand) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AlanyaColors.gold,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.back_hand,
                        color: Colors.white, size: 14),
                  ),
                ],
                if (partage) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AlanyaColors.forest,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.screen_share,
                        color: Colors.white, size: 14),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder({
    required String name,
    required bool isLarge,
    String? avatarUrl,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(isLarge ? 16 : 12),
      ),
      child: Center(
        child: AvatarCircle(
          name: name,
          avatarUrl: avatarUrl,
          radius: isLarge ? 40 : 24,
          backgroundColor: AlanyaColors.terracotta.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return ListenableBuilder(
      listenable: context.read<MeetingController>(),
      builder: (_, __) {
        final ctrl = context.read<MeetingController>();
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 16,
            runSpacing: 12,
            children: [
              // Micro
              _controlButton(
                icon: ctrl.isMuted ? Icons.mic_off : Icons.mic,
                label: ctrl.isMuted ? "Activer" : "Muet",
                isActive: !ctrl.isMuted,
                onTap: ctrl.toggleMute,
              ),
              // Caméra (vidéo uniquement)
              if (ctrl.activeIsVideo)
                _controlButton(
                  icon: ctrl.isCameraOff ? Icons.videocam_off : Icons.videocam,
                  label: ctrl.isCameraOff ? "Caméra off" : "Caméra",
                  isActive: !ctrl.isCameraOff,
                  onTap: ctrl.toggleCamera,
                ),
              // Bascule caméra avant/arrière (vidéo uniquement)
              if (ctrl.activeIsVideo)
                _controlButton(
                  icon: Icons.cameraswitch,
                  label: "Retourner",
                  // Actif pour signaler que le bouton est utilisable (il
                  // paraissait désactivé avec son fond gris).
                  isActive: true,
                  onTap: () => ctrl.switchCamera(),
                ),
              // Haut-parleur
              _controlButton(
                icon: ctrl.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                label: "Haut-parleur",
                isActive: ctrl.isSpeakerOn,
                onTap: () => ctrl.toggleSpeaker(),
              ),
              // Lever la main
              _controlButton(
                icon: ctrl.myHandRaised
                    ? Icons.back_hand
                    : Icons.back_hand_outlined,
                label: "Main",
                isActive: ctrl.myHandRaised,
                onTap: ctrl.toggleHandRaised,
              ),
              // Quitter
              _controlButton(
                icon: Icons.call_end,
                label: "Quitter",
                isActive: false,
                isLeave: true,
                onTap: _leave,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isLeave = false,
  }) {
    final bgColor = isLeave
        ? Colors.red
        : isActive
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08);
    final iconColor = isLeave
        ? Colors.white
        : isActive
            ? Colors.white
            : Colors.white54;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  /// Colonne de droite d'une ligne de la fiche participants : ce que fait la
  /// personne, dans l'ordre où on le cherche — sa main, son écran, son micro.
  ///
  /// Le micro y figure TOUJOURS, les deux autres seulement quand ils ont lieu
  /// d'être : c'est la fiche qu'on ouvre pour savoir qui demande la parole
  /// quand le bandeau n'annonce qu'un décompte.
  Widget _etatParticipant({
    required bool muted,
    required bool hand,
    required bool partage,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hand) ...[
          const Icon(Icons.back_hand, color: AlanyaColors.gold, size: 18),
          const SizedBox(width: 10),
        ],
        if (partage) ...[
          // `forestLight` et non `forest` : le vert du thème se lit mal sur le
          // fond sombre de la salle — la palette le dit déjà pour l'écran
          // d'appel. Ici l'icône n'a pas de pastille pleine pour la porter.
          const Icon(Icons.screen_share,
              color: AlanyaColors.forestLight, size: 18),
          const SizedBox(width: 10),
        ],
        Icon(
          muted ? Icons.mic_off : Icons.mic,
          color: muted ? Colors.red : Colors.white54,
          size: 20,
        ),
      ],
    );
  }

  void _showChat() {
    final ctrl = context.read<MeetingController>();
    ctrl.setChatOpen(true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _MeetingChatPanel(controller: ctrl);
      },
    ).whenComplete(() => ctrl.setChatOpen(false));
  }

  void _showParticipants() {
    final me = context.read<AuthController>().user;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: context.read<MeetingController>(),
          builder: (_, __) {
            final ctrl = context.read<MeetingController>();
            // Liste des participants présents (et non des seuls noms résolus).
            final peerIds = ctrl.peerIds;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text("Participants",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ),
                        Text("${ctrl.participantCount}",
                            style: const TextStyle(color: Colors.white54)),
                        // Faire entrer quelqu'un EN COURS de réunion, sans la
                        // quitter. L'organisateur AJOUTE, un participant
                        // PROPOSE — deux gestes différents, deux libellés
                        // différents, et c'est le serveur qui tranche vraiment.
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: ctrl.jeSuisOrganisateur
                              ? "Ajouter un participant"
                              : "Proposer un participant",
                          icon: Icon(
                            ctrl.jeSuisOrganisateur
                                ? Icons.person_add_alt_1
                                : Icons.person_add_alt,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            // La feuille se referme d'abord : deux feuilles
                            // modales empilées laisseraient le sélecteur de
                            // contacts sous celle-ci.
                            Navigator.of(ctx).pop();
                            if (ctrl.jeSuisOrganisateur) {
                              _ajouterParticipants();
                            } else {
                              _proposerParticipant();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Moi
                        ListTile(
                          leading: AvatarCircle(
                            name: me?.pseudo ?? "Moi",
                            avatarUrl: me?.avatarUrl,
                            radius: 18,
                            backgroundColor: AlanyaColors.terracotta,
                          ),
                          title: Text(me?.pseudo ?? "Vous",
                              style: const TextStyle(color: Colors.white)),
                          trailing: _etatParticipant(
                            muted: ctrl.isMuted,
                            hand: ctrl.myHandRaised,
                            partage: false,
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 1),
                        // Autres
                        ...peerIds.map((peerId) {
                          final name =
                              ctrl.participantNames[peerId] ?? "Participant";
                          final avatar = ctrl.participantAvatars[peerId];
                          final muted = ctrl.isPeerMuted(peerId);
                          return ListTile(
                            leading: AvatarCircle(
                              name: name,
                              avatarUrl: avatar,
                              radius: 18,
                              backgroundColor: AlanyaColors.forest,
                            ),
                            title: Text(name,
                                style: const TextStyle(color: Colors.white)),
                            trailing: _etatParticipant(
                              muted: muted,
                              hand: ctrl.isHandRaised(peerId),
                              partage: ctrl.isSharingScreen(peerId),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Panneau de chat de la réunion (éphémère, style Google Meet).
class _MeetingChatPanel extends StatefulWidget {
  const _MeetingChatPanel({required this.controller});
  final MeetingController controller;

  @override
  State<_MeetingChatPanel> createState() => _MeetingChatPanelState();
}

class _MeetingChatPanelState extends State<_MeetingChatPanel> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  /// Nombre de messages au dernier recalage du défilement. Voir [build].
  int _dernierCompte = 0;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Envoie et vide le champ. RIEN N'EST AFFICHÉ ICI : le message revient par le
  /// serveur, qui le renvoie à toute la salle, l'expéditeur compris. C'est ce
  /// retour qui l'ajoute au fil — et donc son arrivée, et non ce clic, qui fait
  /// descendre le défilement.
  void _send() {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    widget.controller.sendChatMessage(text);
    _inputCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (_, __) {
          final messages = widget.controller.chatMessages;
          /*
           * ⚠️ LE DÉFILEMENT NE SE RECALE QUE SI UN MESSAGE EST ARRIVÉ.
           *
           * Le contrôleur notifie CHAQUE SECONDE — c'est son minuteur de salle
           * qui bat — et ce panneau se reconstruit d'autant. Recaler à chaque
           * reconstruction arrachait le fil des mains de qui remontait le lire :
           * une seconde plus tard, il était rejeté tout en bas.
           */
          if (messages.length != _dernierCompte) {
            _dernierCompte = messages.length;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollCtrl.hasClients) {
                _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
              }
            });
          }
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Poignée
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Messages de la réunion",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                Flexible(
                  child: messages.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              "Aucun message. Démarre la conversation.",
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            return _ChatBubble(message: m);
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputCtrl,
                          style: const TextStyle(color: Colors.white),
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 4,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: "Ton message…",
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: AlanyaColors.forest,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _send,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final MeetingChatMessage message;

  String _time(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(local.hour)}:${two(local.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.mine;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine
              ? AlanyaColors.forest
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isMine ? const Radius.circular(14) : Radius.zero,
            bottomRight: isMine ? Radius.zero : const Radius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Text(
                message.fromName,
                style: const TextStyle(
                  color: AlanyaColors.gold,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            Text(
              message.text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              _time(message.sentAt),
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wrapper simple pour afficher un flux WebRTC.
class RTCVideoRendererObject extends StatefulWidget {
  const RTCVideoRendererObject({
    super.key,
    required this.stream,
    this.estUnEcran = false,
  });
  final MediaStream stream;

  /// Ce flux est un ÉCRAN PARTAGÉ, et non un visage. Deux conséquences, et
  /// c'est tout le sujet :
  ///
  ///  - l'image est montrée EN ENTIER (`contain`) au lieu d'être rognée pour
  ///    remplir la case. Un visage recadré reste un visage ; un écran recadré
  ///    perd la barre d'outils, la ligne de code ou la colonne du tableau
  ///    qu'on partageait justement ;
  ///  - elle n'est JAMAIS retournée en miroir : on y lit du texte.
  ///
  /// Le drapeau vient du verbe serveur `meeting_screen` et de nulle part
  /// ailleurs : la piste d'un écran emprunte le même tuyau que celle d'une
  /// caméra, et rien dans WebRTC ne dit ce qu'elle montre.
  final bool estUnEcran;

  @override
  State<RTCVideoRendererObject> createState() => _RTCVideoRendererObjectState();
}

class _RTCVideoRendererObjectState extends State<RTCVideoRendererObject> {
  final _renderer = RTCVideoRenderer();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // ⚠️ ORDRE IMPORTANT : il faut initialiser le renderer AVANT de lui affecter
    // un flux. Affecter srcObject avant initialize() ne crée pas de texture et
    // la vidéo ne s'affiche jamais (écran figé/chargement infini), même si le
    // flux circule. C'est l'ordre utilisé par l'écran d'appel, qui fonctionne.
    await _renderer.initialize();
    _renderer.srcObject = widget.stream;
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void didUpdateWidget(covariant RTCVideoRendererObject oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le flux peut changer (négociation qui aboutit, bascule de caméra) une
    // fois le renderer déjà initialisé : on réaffecte sans le recréer.
    if (_initialized && oldWidget.stream != widget.stream) {
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return RTCVideoView(
      _renderer,
      // Écrit noir sur blanc plutôt que laissé à la valeur par défaut : le jour
      // où l'on retournera la vignette de sa propre caméra — c'est l'usage —,
      // il faudra que ce faux-là reste vrai pour un écran.
      mirror: false,
      objectFit: widget.estUnEcran
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}
