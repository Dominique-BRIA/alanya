import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/ringtone_service.dart';
import '../../../core/voice_recorder.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../media/media_repository.dart';
import '../call_controller.dart';

/// LE RÉPONDEUR DU CORRESPONDANT — écouter son accueil, lui laisser un message.
///
/// 🔴 CE QU'ELLE REMPLACE : rien. Un appel vers quelqu'un en absence sonnait
/// soixante secondes dans le vide, puis raccrochait tout seul. L'accueil
/// existait en base, le serveur l'envoyait, le mobile ne le lisait pas.
///
/// ⚠️ ELLE S'OUVRE APRÈS LA FIN DE L'APPEL, et c'est normal : l'appel est clos
/// dès le départ côté serveur — il n'a jamais sonné. C'est pour cela que la
/// session de répondeur survit à `_clear()` et que cette feuille vit dans
/// `CallListener`, au-dessus de l'écran d'appel, et non dedans : l'écran
/// d'appel se referme, elle doit rester.
class FeuilleRepondeur extends StatefulWidget {
  const FeuilleRepondeur({super.key});

  @override
  State<FeuilleRepondeur> createState() => _FeuilleRepondeurState();
}

class _FeuilleRepondeurState extends State<FeuilleRepondeur> {
  final VoiceRecorder _enregistreur = VoiceRecorder();

  /// Ce qui joue en ce moment, pour basculer l'icône du bouton d'écoute.
  bool _ecoute = false;
  bool _enregistre = false;
  bool _envoi = false;

  /// Le minuteur d'affichage. ⚠️ Il ne MESURE rien : la durée qui fait foi est
  /// celle de l'enregistreur, pauses exclues. Ce timer ne fait que redessiner.
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    /*
     * 🔴 L'ACCUEIL PART TOUT SEUL — sans quoi « tomber sur le répondeur » n'a
     * pas lieu. Tomber sur un répondeur, c'est l'ENTENDRE ; ce n'est pas
     * trouver un bouton qui propose de l'entendre. La feuille s'ouvrait muette
     * derrière un triangle « lecture » que rien ne distinguait d'un appel
     * manqué ordinaire : le serveur envoyait bien l'accueil, le mobile
     * l'affichait bien, mais personne ne l'entendait sans un second geste.
     *
     * ⚠️ APRÈS LA PREMIÈRE IMAGE, et non pendant `initState` : la session se lit
     * sur le contrôleur fourni par le contexte. `dispose` coupe ensuite toute
     * lecture encore en cours si la feuille est refermée.
     *
     * ⚠️ UNE SEULE FOIS. `_ecouterAccueil` BASCULE lecture/arrêt : l'appeler une
     * seconde fois couperait ce qu'on vient de lancer.
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ecoute) return;
      final url = context.read<CallController>().repondeur?.accueilUrl;
      if (url == null || url.isEmpty) return;
      unawaited(_ecouterAccueil(url));
    });
  }

  @override
  void dispose() {
    _tic?.cancel();
    // 🔴 INDISPENSABLE. L'accueil ne boucle pas, mais il dure jusqu'à trente
    // secondes : il survivrait à la fermeture de la feuille et continuerait
    // par-dessus l'écran suivant, sans plus aucun bouton pour l'arrêter.
    unawaited(RingtoneService.instance.stop());
    // Un enregistrement abandonné doit relâcher le micro, sinon la prochaine
    // ouverture échoue sur une ressource occupée.
    if (_enregistreur.enCours) unawaited(_enregistreur.stop());
    super.dispose();
  }

  Future<void> _ecouterAccueil(String url) async {
    if (_ecoute) {
      await RingtoneService.instance.stop();
      if (mounted) setState(() => _ecoute = false);
      return;
    }
    setState(() => _ecoute = true);
    // ⚠️ `apercu` ET NON `startIncoming` : un accueil a une fin. Le faire
    // boucler reprendrait le défaut déjà payé deux fois par ce dépôt — la
    // lecture d'un centre vocal et la vidéo d'un statut : une boucle
    // n'arrivant jamais à son terme, rien ne vient jamais la refermer.
    await RingtoneService.instance.apercuRepondeur(url: url);
  }

  Future<void> _basculerEnregistrement() async {
    if (_enregistre) return _terminerEtEnvoyer();

    // L'accueil et le micro ne cohabitent pas : on coupe avant d'ouvrir.
    await RingtoneService.instance.stop();
    if (mounted) setState(() => _ecoute = false);

    final ok = await _enregistreur.start();
    if (!mounted) return;
    if (!ok) {
      // Micro refusé ou indisponible : le dire, plutôt que de laisser un bouton
      // qui ne fait rien.
      showAppSnackBar(tr(context, 'vm_failed'));
      return;
    }
    setState(() => _enregistre = true);
    _tic = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _terminerEtEnvoyer() async {
    _tic?.cancel();
    _tic = null;
    // Saisis AVANT le premier `await` : après, le contexte peut être démonté.
    final controleur = context.read<CallController>();
    final medias = context.read<MediaRepository>();

    setState(() {
      _enregistre = false;
      _envoi = true;
    });

    try {
      final capture = await _enregistreur.stop();
      if (capture == null) {
        if (mounted) setState(() => _envoi = false);
        return;
      }
      // ⚠️ DEUX TEMPS, ET C'EST LE CONTRAT DU SERVEUR : on téléverse d'abord le
      // média, on RATTACHE ensuite son identifiant à l'appel. La route du
      // répondeur ne reçoit aucun octet — elle refuse d'ailleurs tout ce qui
      // n'est pas audio.
      final media = await medias.upload(
        capture.bytes,
        "repondeur-${DateTime.now().millisecondsSinceEpoch}.m4a",
        "audio/mp4",
        durationMs: capture.durationMs,
      );
      await controleur.deposerMessage(media.id);
      if (!mounted) return;
      showAppSnackBar(tr(context, 'vm_sent'));
      controleur.fermerRepondeur();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      // Le serveur porte des refus lisibles — appel décroché entre-temps,
      // message déjà laissé, appel trop ancien. Son texte vaut mieux qu'un
      // message générique : il dit POURQUOI.
      showAppSnackBar(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      showAppSnackBar(tr(context, 'vm_failed'));
    }
  }

  String get _duree {
    final d = _enregistreur.duree;
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CallController>().repondeur;
    // La session peut disparaître pendant que la feuille est ouverte — un autre
    // appareil, ou la fermeture elle-même. On ne dessine pas dans le vide.
    if (session == null) return const SizedBox.shrink();

    final nom = session.nomCorrespondant.trim();
    final titre = session.absence
        ? tr(context, 'vm_absent', {'nom': nom})
        : tr(context, 'vm_no_answer', {'nom': nom});
    final accueil = session.accueilUrl;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: faintOf(context, Colors.black26),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'vm_title'),
              style: const TextStyle(fontSize: 13, letterSpacing: 0.4),
            ),
            const SizedBox(height: 4),
            Text(
              titre,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'vm_hint'),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: mutedOf(context, Colors.black54),
              ),
            ),
            const SizedBox(height: 18),

            // Écouter l'accueil — absent quand il n'y en a pas, plutôt que
            // grisé : une action impossible ne doit pas être proposée.
            if (accueil != null)
              OutlinedButton.icon(
                onPressed: _envoi ? null : () => _ecouterAccueil(accueil),
                icon: Icon(
                  _ecoute ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(tr(context, 'vm_listen')),
              ),
            if (accueil != null) const SizedBox(height: 10),

            FilledButton.icon(
              onPressed: _envoi ? null : _basculerEnregistrement,
              icon: Icon(_enregistre ? Icons.send_rounded : Icons.mic_rounded),
              label: Text(
                _enregistre
                    ? "${tr(context, 'send')}  ·  $_duree"
                    : tr(context, 'vm_record'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _envoi
                  ? null
                  : () => context.read<CallController>().fermerRepondeur(),
              child: Text(tr(context, 'cancel')),
            ),
            if (_envoi)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}
