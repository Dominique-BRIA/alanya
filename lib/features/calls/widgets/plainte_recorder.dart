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
import 'ivr_panel.dart';
import '../plaintes_repository.dart';

/// Les états visibles d'une plainte vocale, du bip à l'envoi.
enum _EtatPlainte { bip, enregistrement, pause, relecture, envoi, echec }

/// Enregistrement d'une plainte vocale, sur la touche 0 d'un centre vocal.
///
/// 🔴 **IL PREND LA PLACE DE `IvrMessageBand`, IL NE FLOTTE PAS AU-DESSUS.**
///
/// Le pavé numérique est un `Expanded` qui prend « ce qui reste » : tout widget
/// ajouté au-dessus lui prendrait sa hauteur et le ferait rétrécir — défaut
/// signalé deux fois (17/08 puis 18/08/2026), qu'un test surveille. La bande de
/// message, elle, réserve déjà **52 points** en permanence : s'y installer ne
/// coûte donc rien aux touches. Les deux ne peuvent pas coexister — `ivr_record`
/// efface le message en posant l'étape.
///
/// ⚠️ **UNE PREMIÈRE VERSION FLOTTAIT EN `Stack` + `Clip.none`, ET ELLE ÉTAIT
/// INVISIBLE.** Le panneau était pourtant construit et vivant : c'est lui qui
/// joue le bip, et le bip s'entendait. Mais dans une `Column`, les enfants
/// déclarés APRÈS se peignent par-dessus — le pavé recouvrait tout le
/// débordement vers le bas. « Ni le minuteur ni rien », signalé sur device le
/// 20/08/2026. **Un débordement n'est pas un emplacement.**
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
  /// ⚠️ **LA HAUTEUR EST IMPOSÉE, ET C'EST ELLE QUI DESSINE CE PANNEAU.** Il
  /// prend la place de `IvrMessageBand`, dont les 52 points sont déjà réservés
  /// sur la hauteur du pavé numérique. Dépasser reviendrait à rogner les
  /// touches — ce que le user a explicitement exclu et qu'un test surveille.
  /// D'où UNE SEULE LIGNE : pastille, minuteur, puis les actions en icônes.
  Widget build(BuildContext context) {
    return SizedBox(
      height: IvrMessageBand.hauteur,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pastille(),
              const SizedBox(width: 6),
              // `Flexible` : un message d'échec n'a aucune longueur garantie, et
              // un débordement ferait passer la rayure jaune et noire de Flutter
              // par-dessus le pavé.
              Flexible(child: _texteEtat()),
              const SizedBox(width: 6),
              ..._actions(),
            ],
          ),
        ),
      ),
    );
  }

  /// Le point qui dit l'état d'un coup d'œil : rouge quand ça enregistre
  /// vraiment, blanc en pause — sinon rien ne distinguerait les deux.
  Widget _pastille() {
    final enregistre = _etat == _EtatPlainte.enregistrement;
    return Icon(
      _etat == _EtatPlainte.echec ? Icons.error_outline : Icons.mic,
      size: 16,
      color: _etat == _EtatPlainte.echec
          ? Colors.orangeAccent
          : (enregistre ? Colors.redAccent : Colors.white70),
    );
  }

  /// Le minuteur, ou le motif d'un échec.
  ///
  /// ⚠️ Sur une seule ligne, le CHRONO prime sur la phrase : c'est lui qu'on
  /// regarde en parlant. Les libellés sont donc courts, et le message complet
  /// n'apparaît qu'en cas d'échec, où il n'y a plus de durée à montrer.
  Widget _texteEtat() {
    if (_etat == _EtatPlainte.echec) {
      return Text(
        _erreur ?? "Échec",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
      );
    }
    final libelle = switch (_etat) {
      _EtatPlainte.bip => "Annonce…",
      _EtatPlainte.enregistrement => "",
      _EtatPlainte.pause => "Pause",
      _EtatPlainte.relecture => "Écoutez",
      _EtatPlainte.envoi => "Envoi…",
      _EtatPlainte.echec => "",
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (libelle.isNotEmpty) ...[
          Flexible(
            child: Text(
              libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          _mmss(_duree),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            // Chiffres à chasse fixe : sans eux le minuteur tressaute à chaque
            // seconde, et tout ce qui le suit bouge avec.
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Les actions, en ICÔNES et non en boutons libellés : sur une seule ligne de
  /// 52 points, trois libellés ne rentrent pas, et les tronquer les rendrait
  /// illisibles. L'icône seule est comprise partout — ce sont les symboles d'un
  /// magnétophone.
  List<Widget> _actions() {
    switch (_etat) {
      case _EtatPlainte.bip:
        return const [SizedBox(width: 4)];
      case _EtatPlainte.envoi:
        return const [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ];
      case _EtatPlainte.enregistrement:
      case _EtatPlainte.pause:
        return [
          _bouton(
            icone: _etat == _EtatPlainte.pause ? Icons.play_arrow : Icons.pause,
            infobulle: _etat == _EtatPlainte.pause ? "Reprendre" : "Pause",
            onTap: _basculerPause,
          ),
          _bouton(icone: Icons.stop, infobulle: "Terminer", onTap: _arreter),
        ];
      case _EtatPlainte.relecture:
        final joue = _relecture.state == PlayerState.playing;
        return [
          _bouton(
            icone: joue ? Icons.pause : Icons.play_arrow,
            infobulle: joue ? "Pause" : "Écouter",
            onTap: _cheminRelecture == null ? null : _basculerRelecture,
          ),
          _bouton(
            icone: Icons.refresh,
            infobulle: "Refaire",
            onTap: _recommencer,
          ),
          _bouton(
            icone: Icons.send,
            infobulle: "Envoyer",
            accent: true,
            onTap: _envoyer,
          ),
        ];
      case _EtatPlainte.echec:
        return [
          _bouton(
            icone: Icons.refresh,
            infobulle: "Refaire",
            onTap: _recommencer,
          ),
          // « Réessayer » n'apparaît que s'il y a quelque chose à renvoyer : un
          // échec de micro n'a produit aucun fichier.
          if (_octets != null)
            _bouton(
              icone: Icons.send,
              infobulle: "Réessayer",
              accent: true,
              onTap: _envoyer,
            ),
        ];
    }
  }

  Widget _bouton({
    required IconData icone,
    required String infobulle,
    required VoidCallback? onTap,
    bool accent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: infobulle,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent
                  ? Colors.redAccent.withValues(alpha: 0.85)
                  : Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icone,
              size: 17,
              color: onTap == null ? Colors.white38 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
