import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/ringtone_service.dart';
import '../../../core/voice_recorder.dart';
import '../../media/media_repository.dart';
import '../call_controller.dart';
import '../plaintes_repository.dart';

/// Les états visibles d'une plainte vocale, du bip à l'envoi.
enum _EtatPlainte { bip, enregistrement, pause, relecture, envoi, echec }

/// Enregistrement d'une plainte vocale, sur la touche 0 d'un centre vocal.
///
/// 🔴 **POSÉ EN SURCOUCHE, ET C'EST TOUT L'ENJEU DE MISE EN PAGE.** Le pavé
/// numérique est un `Expanded` qui prend « ce qui reste » : tout widget ajouté
/// au-dessus lui prendrait sa hauteur, et le ferait rétrécir — le défaut
/// signalé deux fois (17/08 puis 18/08/2026), qu'un test surveille désormais.
/// Ce panneau ne participe donc PAS à la colonne : il flotte dans l'espace déjà
/// réservé entre le nom du centre et la bande « Accueil », qui est vide pendant
/// un enregistrement. La géométrie de l'écran ne change pas d'un pixel.
///
/// ⚠️ **L'ENREGISTREMENT NE DÉMARRE PAS À L'APPUI SUR 0**, mais à la FIN DU BIP
/// — demande explicite du user. Le serveur donne le départ et l'URL ; c'est ici
/// qu'on enchaîne, parce que seul le lecteur sait quand l'annonce se termine.
/// Sans bip — variable d'environnement absente — on démarre tout de suite : une
/// configuration oubliée ne doit pas rendre la touche inutilisable.
class PlainteRecorder extends StatefulWidget {
  const PlainteRecorder({
    super.key,
    required this.session,
    required this.onTermine,
  });

  final IvrSession session;

  /// Appelé quand il n'y a plus rien à montrer — plainte envoyée, ou abandon.
  final VoidCallback onTermine;

  @override
  State<PlainteRecorder> createState() => _PlainteRecorderState();
}

class _PlainteRecorderState extends State<PlainteRecorder> {
  final VoiceRecorder _recorder = VoiceRecorder();
  final AudioPlayer _relecture = AudioPlayer();

  _EtatPlainte _etat = _EtatPlainte.bip;
  Timer? _battement;
  Duration _duree = Duration.zero;

  /// Le fichier obtenu à l'arrêt, gardé pour la réécoute ET pour l'envoi.
  Uint8List? _octets;
  String? _cheminRelecture;

  /// 🔴 POSÉE UNE FOIS À L'ARRÊT DU MICRO, JAMAIS REGÉNÉRÉE. C'est elle qui rend
  /// l'envoi idempotent : un réessai après échec réseau réutilise la même clé,
  /// et le serveur rend la plainte déjà enregistrée au lieu d'en créer une
  /// seconde. La refabriquer à chaque tentative annulerait toute la garantie.
  String? _cleEnvoi;

  String? _erreur;

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  @override
  void dispose() {
    _battement?.cancel();
    // ⚠️ L'ÉCRAN PEUT PARTIR PENDANT L'ENREGISTREMENT — l'appelant raccroche,
    // l'agent décroche, le système tue la vue. Sans cet abandon, le micro
    // resterait pris et le fichier temporaire ne serait jamais effacé.
    _recorder.cancel();
    _relecture.dispose();
    _effacerFichierRelecture();
    super.dispose();
  }

  void _effacerFichierRelecture() {
    final chemin = _cheminRelecture;
    _cheminRelecture = null;
    if (chemin == null) return;
    try {
      final f = File(chemin);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Un fichier temporaire qui résiste n'est pas un motif d'échec.
    }
  }

  /// Bip puis micro. Les deux chemins se rejoignent sur [_lancerMicro].
  Future<void> _demarrer() async {
    final bip = widget.session.bipEnregistrementUrl;
    if (bip == null || bip.isEmpty) {
      await _lancerMicro();
      return;
    }
    // `playIvrPrompt` porte le contexte audio de l'appel — flux voix, haut-
    // parleur. Le rejouer avec un lecteur neuf ferait sortir le bip par
    // l'écouteur, le piège du 12/08/2026.
    unawaited(
      RingtoneService.instance.playIvrPrompt(
        bip,
        loop: false,
        onComplete: () {
          if (mounted) _lancerMicro();
        },
      ),
    );
    // Filet : un bip injoignable ne rend jamais la main. Sans ce délai,
    // l'appelant resterait devant « Annonce en cours… » indéfiniment.
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (mounted && _etat == _EtatPlainte.bip) _lancerMicro();
    });
  }

  Future<void> _lancerMicro() async {
    if (!mounted || _etat != _EtatPlainte.bip) return;
    await RingtoneService.instance.stopIvr();
    final ok = await _recorder.start();
    if (!mounted) return;
    if (!ok) {
      // Permission refusée, ou plateforme sans micro. On le DIT : un panneau
      // qui reste à zéro sans rien expliquer se lit comme une panne.
      setState(() {
        _etat = _EtatPlainte.echec;
        _erreur = "Micro indisponible. Autorise l'accès dans les réglages.";
      });
      return;
    }
    setState(() => _etat = _EtatPlainte.enregistrement);
    _reglerBattement();
  }

  /// Le minuteur d'affichage. Il lit la durée DU RECORDER et ne la calcule pas
  /// lui-même : c'est la même mesure que celle qui partira au serveur, donc
  /// l'appelant ne peut pas voir un chiffre et en envoyer un autre.
  void _reglerBattement() {
    _battement?.cancel();
    if (_etat != _EtatPlainte.enregistrement) return;
    _battement = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final d = _recorder.duree;
      setState(() => _duree = d);
      if (d.inMilliseconds >= widget.session.plainteMaxMs) _arreter();
    });
  }

  Future<void> _basculerPause() async {
    if (_etat == _EtatPlainte.enregistrement) {
      if (await _recorder.pause()) {
        _battement?.cancel();
        if (mounted) setState(() => _etat = _EtatPlainte.pause);
      }
    } else if (_etat == _EtatPlainte.pause) {
      if (await _recorder.resume()) {
        if (mounted) setState(() => _etat = _EtatPlainte.enregistrement);
        _reglerBattement();
      }
    }
  }

  Future<void> _arreter() async {
    _battement?.cancel();
    final resultat = await _recorder.stop();
    if (!mounted) return;
    // ⚠️ Un fichier VIDE ou illisible n'est pas envoyable. `stop` rend `null`
    // aussi bien pour un micro muet que pour un fichier absent : dans les deux
    // cas il n'y a rien à écouter, et rien à déposer.
    if (resultat == null || resultat.bytes.isEmpty) {
      setState(() {
        _etat = _EtatPlainte.echec;
        _erreur = "Enregistrement vide. Réessaie.";
      });
      return;
    }
    _octets = resultat.bytes;
    _duree = Duration(milliseconds: resultat.durationMs);
    _cleEnvoi ??= _fabriquerCle();
    await _preparerRelecture();
    if (mounted) setState(() => _etat = _EtatPlainte.relecture);
  }

  /// Écrit les octets sur disque : la réécoute a besoin d'un fichier, et
  /// `VoiceRecorder.stop` a déjà effacé le sien.
  Future<void> _preparerRelecture() async {
    try {
      final dir = await getTemporaryDirectory();
      final chemin =
          "${dir.path}/plainte-${DateTime.now().millisecondsSinceEpoch}.m4a";
      await File(chemin).writeAsBytes(_octets!);
      _cheminRelecture = chemin;
    } catch (_) {
      // Sans fichier, on perd la réécoute mais PAS l'envoi : le bouton de
      // lecture se grisera, le reste fonctionne.
      _cheminRelecture = null;
    }
  }

  Future<void> _basculerRelecture() async {
    final chemin = _cheminRelecture;
    if (chemin == null) return;
    if (_relecture.state == PlayerState.playing) {
      await _relecture.pause();
    } else {
      await _relecture.play(DeviceFileSource(chemin));
    }
    if (mounted) setState(() {});
  }

  /// Recommencer : on jette tout, y compris la clé d'envoi.
  ///
  /// ⚠️ C'est le SEUL endroit qui a le droit de la jeter — c'est un nouvel
  /// enregistrement, donc une nouvelle plainte. La jeter ailleurs (à un réessai
  /// d'envoi, par exemple) casserait l'idempotence.
  Future<void> _recommencer() async {
    await _relecture.stop();
    _effacerFichierRelecture();
    _octets = null;
    _cleEnvoi = null;
    _erreur = null;
    _duree = Duration.zero;
    setState(() => _etat = _EtatPlainte.bip);
    await _lancerMicroApresRemiseAZero();
  }

  Future<void> _lancerMicroApresRemiseAZero() async {
    // On ne rejoue PAS le bip : l'appelant vient de l'entendre, et le lui
    // réimposer à chaque essai serait pénible.
    await _lancerMicro();
  }

  Future<void> _envoyer() async {
    final octets = _octets;
    final cle = _cleEnvoi;
    if (octets == null || cle == null) return;
    // Saisis AVANT tout `await` : ce panneau peut disparaître pendant l'envoi.
    final medias = context.read<MediaRepository>();
    final plaintes = context.read<PlaintesRepository>();
    final centerId = widget.session.centerId;

    await _relecture.stop();
    setState(() {
      _etat = _EtatPlainte.envoi;
      _erreur = null;
    });

    try {
      final media = await medias.upload(
        octets,
        "plainte-$cle.m4a",
        "audio/mp4",
        durationMs: _duree.inMilliseconds,
      );
      await plaintes.deposer(
        centerId: centerId,
        mediaId: media.id,
        cleEnvoi: cle,
        dureeMs: _duree.inMilliseconds,
      );
      if (!mounted) return;
      widget.onTermine();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _etat = _EtatPlainte.echec;
          _erreur = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _etat = _EtatPlainte.echec;
          // ⚠️ On garde la clé : « Réessayer » réutilisera la MÊME, et le
          // serveur ne créera pas de doublon même si la première tentative
          // avait en fait abouti et que seule la réponse s'est perdue.
          _erreur = "Envoi impossible. Réessaie.";
        });
      }
    }
  }

  String _fabriquerCle() {
    final alea = Random();
    final suffixe = List.generate(
      8,
      (_) => alea.nextInt(36).toRadixString(36),
    ).join();
    return "pl-${DateTime.now().millisecondsSinceEpoch}-$suffixe";
  }

  String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_ligneEtat(), const SizedBox(height: 8), _actions()],
      ),
    );
  }

  Widget _ligneEtat() {
    final enregistre = _etat == _EtatPlainte.enregistrement;
    final texte = switch (_etat) {
      _EtatPlainte.bip => "Annonce en cours…",
      _EtatPlainte.enregistrement => "Parlez, on vous écoute",
      _EtatPlainte.pause => "En pause",
      _EtatPlainte.relecture => "Réécoutez avant d'envoyer",
      _EtatPlainte.envoi => "Envoi…",
      _EtatPlainte.echec => _erreur ?? "Échec",
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Le point rouge ne clignote QUE pendant l'enregistrement réel : en
        // pause il reste fixe, sinon rien ne distinguerait les deux états.
        Icon(
          _etat == _EtatPlainte.echec ? Icons.error_outline : Icons.mic,
          size: 16,
          color: _etat == _EtatPlainte.echec
              ? Colors.orangeAccent
              : (enregistre ? Colors.redAccent : Colors.white70),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            texte,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        if (_etat != _EtatPlainte.echec) ...[
          const SizedBox(width: 10),
          Text(
            _mmss(_duree),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  Widget _actions() {
    switch (_etat) {
      case _EtatPlainte.bip:
        return const SizedBox(height: 32);
      case _EtatPlainte.envoi:
        return const SizedBox(
          height: 32,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _EtatPlainte.enregistrement:
      case _EtatPlainte.pause:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bouton(
              icone: _etat == _EtatPlainte.pause
                  ? Icons.play_arrow
                  : Icons.pause,
              libelle: _etat == _EtatPlainte.pause ? "Reprendre" : "Pause",
              onTap: _basculerPause,
            ),
            const SizedBox(width: 10),
            _bouton(icone: Icons.stop, libelle: "Terminer", onTap: _arreter),
          ],
        );
      case _EtatPlainte.relecture:
        final joue = _relecture.state == PlayerState.playing;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bouton(
              icone: joue ? Icons.pause : Icons.play_arrow,
              libelle: joue ? "Pause" : "Écouter",
              onTap: _cheminRelecture == null ? null : _basculerRelecture,
            ),
            const SizedBox(width: 10),
            _bouton(
              icone: Icons.refresh,
              libelle: "Refaire",
              onTap: _recommencer,
            ),
            const SizedBox(width: 10),
            _bouton(
              icone: Icons.send,
              libelle: "Envoyer",
              accent: true,
              onTap: _envoyer,
            ),
          ],
        );
      case _EtatPlainte.echec:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bouton(
              icone: Icons.refresh,
              libelle: "Refaire",
              onTap: _recommencer,
            ),
            // « Réessayer » n'apparaît que s'il y a quelque chose à renvoyer :
            // un échec de micro n'a produit aucun fichier.
            if (_octets != null) ...[
              const SizedBox(width: 10),
              _bouton(
                icone: Icons.send,
                libelle: "Réessayer",
                accent: true,
                onTap: _envoyer,
              ),
            ],
          ],
        );
    }
  }

  Widget _bouton({
    required IconData icone,
    required String libelle,
    required VoidCallback? onTap,
    bool accent = false,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icone, size: 16),
      label: Text(libelle, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: accent
            ? Colors.redAccent.withValues(alpha: 0.85)
            : Colors.white24,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
