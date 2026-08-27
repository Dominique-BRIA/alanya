import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../../widgets/motif_background.dart';
import '../../../models/meeting.dart';
import '../../auth/auth_controller.dart';
import '../meeting_controller.dart';
import '../meetings_repository.dart';
import '../widgets/tuile_demande.dart';
import 'meeting_room_screen.dart';

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

  /// Demandes EN ATTENTE, telles que le serveur les rend à CETTE personne :
  /// toutes pour l'organisateur, seulement les siennes pour les autres.
  List<MeetingInviteRequest> _demandes = const [];

  /// Écoute des changements de composition annoncés par le serveur.
  StreamSubscription<MeetingComposition>? _compositionSub;

  @override
  void initState() {
    super.initState();
    _meeting = widget.meeting;
    // Partage les avatars connus avec le contrôleur de salle, pour les afficher
    // en l'absence de flux vidéo (le serveur temps réel ne les envoie pas).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MeetingController>().setParticipantAvatars(
            _meeting.participants.map((p) => MapEntry(p.userId, p.avatarUrl)),
          );
      // `_isOrganiser` lit le contexte : il n'est consultable qu'une fois la
      // première frame passée, d'où le chargement des demandes ici et non plus
      // haut dans initState.
      _chargeDemandes();
      _ecouteLaComposition();
    });
  }

  /// CETTE FICHE EST LA SURFACE QUE LE DÉFAUT VISAIT.
  ///
  /// « Participants (N) » et la liste dessous viennent d'une COPIE prise au
  /// chargement. Quand l'organisateur ajoutait quelqu'un depuis un autre
  /// appareil, la route REST écrivait en base sans pouvoir prévenir personne :
  /// il fallait sortir de la fiche et y revenir pour voir la ligne apparaître.
  ///
  /// Le serveur annonce désormais le changement dans la salle, et le contrôleur
  /// le relaie ici. On RELIT alors notre propre copie plutôt que de la
  /// rapiécer : c'est la même source pour tout le monde, et un ajout suivi
  /// d'un retrait ne laisse aucun reste.
  ///
  /// ⚠️ CETTE RÉSERVE EST LEVÉE DEPUIS LE 26/08/2026. L'annonce ne passait que
  /// par la SALLE, donc n'atteignait que les sockets qui y sont inscrites :
  /// ouvrir cette fiche sans être entré dans la réunion n'inscrit dans aucune
  /// salle, et le geste manuel restait le seul recours — ce que le user a
  /// signalé pour les demandes d'invitation.
  ///
  /// Le pont interne sait désormais viser des PERSONNES en plus des salles
  /// (`src/lib/salle-temps-reel.ts`), et le serveur adresse l'annonce à
  /// l'organisateur comme au proposant, où qu'ils soient dans l'application.
  /// Le « tirer pour rafraîchir » reste un filet, plus une nécessité.
  void _ecouteLaComposition() {
    _compositionSub =
        context.read<MeetingController>().compositions.listen((c) {
      if (!mounted || c.meetingId != _meeting.idMeeting) return;
      _refresh();
      // Une demande acceptée ajoute un participant ET retire la demande : la
      // liste d'à côté devient fausse au même instant.
      _chargeDemandes();
    });
  }

  @override
  void dispose() {
    _compositionSub?.cancel();
    super.dispose();
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
      final updated = await context
          .read<MeetingsRepository>()
          .fetchMeeting(_meeting.idMeeting);
      if (mounted) {
        setState(() => _meeting = updated);
        context.read<MeetingController>().setParticipantAvatars(
              updated.participants.map((p) => MapEntry(p.userId, p.avatarUrl)),
            );
      }
    } catch (_) {}
  }

  void _joinMeeting() {
    // Si on est déjà dans cette réunion (salle réduite, ouvre simplement la
    // salle existante sans relancer une négociation WebRTC).
    final mc = context.read<MeetingController>();
    if (mc.activeMeetingId == _meeting.idMeeting && mc.isActive) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MeetingRoomScreen(
            meetingId: _meeting.idMeeting,
            objet: _meeting.objet,
            isVideo: _meeting.isVideo,
            plannedDurationSec: _meeting.duree,
            organiserId: _meeting.organiser.id,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeetingRoomScreen(
          meetingId: _meeting.idMeeting,
          objet: _meeting.objet,
          isVideo: _meeting.isVideo,
          plannedDurationSec: _meeting.duree,
          organiserId: _meeting.organiser.id,
        ),
      ),
    );
  }

  /// Ajoute des participants — organisateur seulement, avant comme pendant.
  ///
  /// Les membres actuels et l'organisateur sont retirés de la liste proposée :
  /// choisir quelqu'un qui est déjà là n'aurait aucun effet, et le lui laisser
  /// faire pour ensuite l'ignorer serait déroutant.
  Future<void> _ajouterParticipants() async {
    final dejaLa = <String>[
      ..._meeting.participants.map((p) => p.publicNumber ?? ""),
      _meeting.organiser.publicNumber ?? "",
    ].where((n) => n.isNotEmpty).toList();

    final numeros = await ContactPickerSheet.show(
      context,
      title: "Ajouter à la réunion",
      confirmLabel: "Ajouter",
      excludeNumbers: dejaLa,
    );
    if (numeros == null || numeros.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      final ajoutes = await context
          .read<MeetingsRepository>()
          .addParticipants(_meeting.idMeeting, numeros);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // Zéro ajout n'est pas une erreur : le serveur écarte sans broncher
            // ceux qui étaient déjà membres. Le dire évite de laisser croire à
            // une panne devant une liste inchangée.
            ajoutes == 0
                ? "Personne à ajouter : ces contacts sont déjà dans la réunion"
                : ajoutes == 1
                    ? "1 participant ajouté et prévenu"
                    : "$ajoutes participants ajoutés et prévenus",
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Un participant PROPOSE quelqu'un ; l'organisateur tranchera.
  ///
  /// Le message de confirmation dit explicitement que l'intéressé n'est pas
  /// prévenu : sans cela, le demandeur croirait avoir invité quelqu'un et
  /// s'étonnerait de son absence.
  Future<void> _proposerParticipant() async {
    final dejaLa = <String>[
      ..._meeting.participants.map((p) => p.publicNumber ?? ""),
      _meeting.organiser.publicNumber ?? "",
    ].where((n) => n.isNotEmpty).toList();

    final numeros = await ContactPickerSheet.show(
      context,
      title: "Proposer à l'organisateur",
      confirmLabel: "Proposer",
      excludeNumbers: dejaLa,
    );
    if (numeros == null || numeros.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      // Une seule personne : chaque proposition se tranche séparément, un lot
      // obligerait l'organisateur à tout accepter ou tout refuser.
      await context
          .read<MeetingsRepository>()
          .requestInvite(_meeting.idMeeting, numeros.first);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Demande envoyée à l'organisateur. La personne n'est pas prévenue tant qu'il n'a pas accepté."),
          duration: Duration(seconds: 6),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Charge les demandes en attente.
  ///
  /// ⚠️ PLUS RÉSERVÉ À L'ORGANISATEUR depuis le 26/08/2026. La route rend
  /// désormais à chacun LES SIENNES — celui qui a proposé quelqu'un suit sa
  /// demande — et c'est le serveur qui filtre, pas cet écran. Le garde-fou
  /// `if (!_isOrganiser) return;` qui était ici empêchait le proposant de voir
  /// quoi que ce soit, quelle que soit la réponse du serveur.
  ///
  /// Sans demande à soi, la liste revient vide : rien ne s'affiche, et personne
  /// n'apprend rien sur les demandes des autres.
  Future<void> _chargeDemandes() async {
    try {
      final d = await context
          .read<MeetingsRepository>()
          .fetchInviteRequests(_meeting.idMeeting);
      if (mounted) {
        setState(() => _demandes = d.where((x) => x.estEnAttente).toList());
      }
    } catch (_) {
      // Silencieux : l'absence de la liste ne doit pas empêcher d'afficher la
      // fiche, qui reste utilisable sans elle.
    }
  }

  /// L'organisateur tranche.
  Future<void> _trancheDemande(MeetingInviteRequest d, bool accepter) async {
    setState(() => _loading = true);
    try {
      await context.read<MeetingsRepository>().decideInviteRequest(
            _meeting.idMeeting,
            d.id,
            accepter: accepter,
          );
      await _refresh();
      await _chargeDemandes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepter
              ? "${d.invite.displayName} a été ajouté et prévenu"
              // On rappelle ici la portée du refus : il vaut pour tout le monde
              // et pour toujours, ce n'est pas un simple « pas maintenant ».
              : "Demande refusée. ${d.invite.displayName} n'en saura rien, et ne pourra plus être proposé."),
          duration: const Duration(seconds: 6),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
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
              child:
                  Text("Terminer", style: TextStyle(color: dangerOf(context)))),
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

  Future<void> _decline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Décliner l'invitation ?"),
        content: const Text("Tu ne rejoindras pas cette réunion."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text("Décliner", style: TextStyle(color: dangerOf(context)))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await context
          .read<MeetingsRepository>()
          .declineMeeting(_meeting.idMeeting);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invitation déclinée")),
        );
        Navigator.of(context).pop(true);
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
                  color: themed(context,
                      light: Colors.white, dark: surfacesOf(context).surface),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: themed(context,
                          light: AlanyaColors.grey200,
                          dark: AlanyaColors.ligne),
                      width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          m.isVideo ? Icons.videocam : Icons.call,
                          color: m.isFinished
                              ? mutedOf(context, Colors.grey)
                              : positiveOf(context),
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
                    _infoRow("Durée prévue", _formatDuration(m.duree)),
                    _infoRow("Début", _formatDateTime(m.startTime)),
                    _infoRow("Organisateur", m.organiser.displayName),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Bouton Rejoindre ---
              if (!m.isFinished)
                ElevatedButton.icon(
                  onPressed: _loading ? null : _joinMeeting,
                  icon: const Icon(Icons.login),
                  label: const Text("Rejoindre la réunion"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: positiveOf(context),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                  ),
                ),
              if (!m.isFinished && !_isOrganiser) ...[
                const SizedBox(height: 12),
                // Un participant ne peut pas ajouter : il PROPOSE, et
                // l'organisateur tranche. Le libellé le dit, pour qu'il ne
                // croie pas avoir invité quelqu'un.
                OutlinedButton.icon(
                  onPressed: _loading ? null : _proposerParticipant,
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: const Text("Proposer un participant"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _decline,
                  icon:
                      Icon(Icons.event_busy_outlined, color: dangerOf(context)),
                  label: Text("Décliner l'invitation",
                      style: TextStyle(color: dangerOf(context))),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
              if (!m.isFinished && _isOrganiser) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _ajouterParticipants,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text("Ajouter des participants"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _end,
                  icon: Icon(Icons.stop_circle_outlined,
                      color: dangerOf(context)),
                  label: Text("Terminer la réunion",
                      style: TextStyle(color: dangerOf(context))),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // --- Demandes en attente ---
              //
              // L organisateur les voit toutes ; chacun des autres ne voit que
              // les siennes, et c est le SERVEUR qui filtre.
              if (_demandes.isNotEmpty) ...[
                Text(
                  _isOrganiser
                      ? "Demandes en attente (${_demandes.length})"
                      : "Tes demandes (${_demandes.length})",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ..._demandes.map(_demandeTile),
                const SizedBox(height: 24),
              ],

              // --- Participants ---
              Text(
                "Participants (${m.participants.length})",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
            child: Text(label,
                style: TextStyle(color: mutedOf(context, Colors.black54))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  /// Une demande en attente, avec les deux seules issues possibles.
  ///
  /// Le sous-titre nomme le DEMANDEUR : c'est ce qui permet à l'organisateur de
  /// juger — la même personne proposée par deux collègues différents n'appelle
  /// pas la même décision.
  /// La tuile vient du composant partage avec la salle : les deux surfaces
  /// doivent proposer les memes gestes aux memes personnes.
  Widget _demandeTile(MeetingInviteRequest d) {
    final moi = context.read<AuthController>().user?.id;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: TuileDemandeInvitation(
        demande: d,
        jeSuisOrganisateur: _isOrganiser,
        jeSuisLeProposant: d.demandeur.id == moi,
        actif: !_loading,
        onAccepter: () => _trancheDemande(d, true),
        onRefuser: () => _confirmeRefus(d),
        onRetirer: () => _retireDemande(d),
      ),
    );
  }

  /// Le proposant retire sa demande.
  ///
  /// ⚠️ SANS CONFIRMATION, contrairement au refus. Retirer sa propre demande ne
  /// détruit rien : la personne pourra être proposée de nouveau, par n'importe
  /// qui. Le refus, lui, est définitif — d'où le dialogue qui le précède.
  ///
  /// ⚠️ L'ÉCHEC EST NORMAL ICI et doit se lire : si l'organisateur a tranché
  /// entre-temps, le serveur refuse et le dit. On relit alors la liste plutôt
  /// que de laisser à l'écran une demande qui n'existe plus.
  Future<void> _retireDemande(MeetingInviteRequest d) async {
    setState(() => _loading = true);
    try {
      await context
          .read<MeetingsRepository>()
          .cancelInviteRequest(_meeting.idMeeting, d.id);
    } on ApiException catch (e) {
      // Le message du serveur tel quel : c'est lui qui sait si l'organisateur
      // a tranché entre-temps, et c'est ce qu'il faut lire.
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Serveur injoignable")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      // Relue dans TOUS LES CAS, y compris après un échec : si le refus vient
      // de ce que l'organisateur a tranché, la demande n'existe plus et doit
      // disparaître de l'écran.
      await _chargeDemandes();
    }
  }

  /// Le refus est confirmé, l'acceptation non.
  ///
  /// Dissymétrie voulue : un refus est IRRÉVERSIBLE — la personne ne pourra
  /// plus jamais être proposée, par personne. Une acceptation, elle, se rattrape
  /// (l'organisateur peut retirer quelqu'un ou terminer la réunion).
  Future<void> _confirmeRefus(MeetingInviteRequest d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Refuser cette demande ?"),
        content: Text(
            "${d.invite.displayName} ne sera pas ajouté et n'en saura rien. "
            "Personne ne pourra plus le proposer pour cette réunion."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text("Refuser", style: TextStyle(color: dangerOf(context)))),
        ],
      ),
    );
    if (ok == true) await _trancheDemande(d, false);
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
          backgroundColor: AlanyaColors.gold,
        ),
        title: Text(p.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(statusText, style: const TextStyle(fontSize: 12)),
        trailing: p.duree != null
            ? Text(_formatDuration(p.duree!),
                style: TextStyle(
                    fontSize: 12, color: mutedOf(context, Colors.black54)))
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
