import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/ringtone_service.dart';
import '../../../core/server_config.dart';
import '../../../core/token_storage.dart';
import '../../../core/voice_recorder.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../calls/repondeur_repository.dart';
import '../../media/media_repository.dart';

/// MON RÉPONDEUR — l'interrupteur, l'absence, et mes messages d'accueil.
///
/// 🔴 CET ÉCRAN N'EXISTAIT PAS SUR MOBILE. Le répondeur était livré côté serveur
/// et côté web depuis le 11/09 : un utilisateur mobile pouvait *subir* le
/// répondeur des autres, jamais régler le sien. Il lui fallait ouvrir le web.
///
/// ⚠️ TOUTES LES RÈGLES VIVENT SUR LE SERVEUR, et cet écran n'en réinvente
/// aucune : poser une absence allume le répondeur, supprimer l'accueil actif
/// l'éteint, et un seul accueil est actif à la fois. On affiche donc CE QUE LE
/// SERVEUR REND après chaque écriture, jamais ce qu'on croit avoir envoyé.
class RepondeurScreen extends StatefulWidget {
  const RepondeurScreen({super.key});

  @override
  State<RepondeurScreen> createState() => _RepondeurScreenState();
}

class _RepondeurScreenState extends State<RepondeurScreen> {
  final VoiceRecorder _enregistreur = VoiceRecorder();

  MonRepondeur? _etat;
  bool _chargement = true;
  bool _envoi = false;
  bool _enregistre = false;
  String? _enEcoute;
  Timer? _tic;

  /// Les durées proposées, en minutes. La dernière est la borne du serveur :
  /// au-delà, ce n'est plus une absence mais un compte injoignable.
  static const _durees = <int>[30, 60, 120, 240, 480, absenceMaxMinutes];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _tic?.cancel();
    unawaited(RingtoneService.instance.stop());
    if (_enregistreur.enCours) unawaited(_enregistreur.stop());
    super.dispose();
  }

  Future<void> _charger() async {
    final depot = context.read<RepondeurRepository>();
    try {
      final etat = await depot.lire();
      if (!mounted) return;
      setState(() {
        _etat = etat;
        _chargement = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _chargement = false);
      showAppSnackBar(tr(context, 'lists_load_error'));
    }
  }

  /// Exécute une écriture et ADOPTE l'état rendu par le serveur.
  ///
  /// ⚠️ ON NE DEVINE JAMAIS L'ÉTAT SUIVANT. Poser une absence allume aussi le
  /// répondeur, supprimer l'accueil actif l'éteint : reconstituer ces effets
  /// côté écran donnerait une seconde version de la règle, qui finirait par
  /// diverger de celle du serveur.
  Future<void> _ecrire(Future<MonRepondeur> Function() action) async {
    setState(() => _envoi = true);
    try {
      final etat = await action();
      if (!mounted) return;
      setState(() {
        _etat = etat;
        _envoi = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      showAppSnackBar(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      showAppSnackBar(tr(context, 'save_failed_short'));
    }
  }

  Future<void> _ecouter(Accueil a) async {
    if (_enEcoute == a.id) {
      await RingtoneService.instance.stop();
      if (mounted) setState(() => _enEcoute = null);
      return;
    }
    final jeton = await TokenStorage().accessToken;
    if (jeton == null || jeton.isEmpty || a.url.isEmpty) return;
    if (!mounted) return;
    setState(() => _enEcoute = a.id);
    // `apercu` : un accueil a une fin, il ne boucle pas.
    await RingtoneService.instance.apercu(
      url: "${ServerConfig.apiBase}${a.url}?token=$jeton",
    );
  }

  Future<void> _basculerEnregistrement() async {
    if (_enregistre) return _terminerAccueil();

    await RingtoneService.instance.stop();
    if (mounted) setState(() => _enEcoute = null);

    final ok = await _enregistreur.start();
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(tr(context, 'vm_failed'));
      return;
    }
    setState(() => _enregistre = true);
    _tic = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _terminerAccueil() async {
    _tic?.cancel();
    _tic = null;
    final depot = context.read<RepondeurRepository>();
    final medias = context.read<MediaRepository>();
    setState(() => _enregistre = false);

    final capture = await _enregistreur.stop();
    if (capture == null || !mounted) return;

    // Deux temps, comme pour un message vocal : on téléverse le média, on
    // déclare ensuite son identifiant au répondeur. La route ne reçoit pas
    // d'octets.
    await _ecrire(() async {
      final media = await medias.upload(
        capture.bytes,
        "accueil-${DateTime.now().millisecondsSinceEpoch}.m4a",
        "audio/mp4",
        durationMs: capture.durationMs,
      );
      return depot.ajouterAccueil(
        mediaId: media.id,
        // Un libellé daté : c'est ce qui distingue deux accueils dans la liste,
        // et personne n'a envie d'en saisir un au moment où il vient de parler.
        libelle: _horodatageCourt(DateTime.now()),
      );
    });
  }

  String _horodatageCourt(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} "
      "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  String get _duree {
    final d = _enregistreur.duree;
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  String _libelleDuree(int minutes) {
    if (minutes < 60) return "$minutes min";
    final h = minutes ~/ 60;
    return "$h h";
  }

  @override
  Widget build(BuildContext context) {
    final etat = _etat;
    final muted = mutedOf(context, Colors.black54);

    return Scaffold(
      appBar: backAppBar(context, tr(context, 'vm_title')),
      body: MotifBackground(
        child: _chargement
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (_envoi) const LinearProgressIndicator(minHeight: 2),

                  SwitchListTile(
                    value: etat?.actif ?? false,
                    onChanged: _envoi
                        ? null
                        : (v) => _ecrire(
                            () =>
                                context.read<RepondeurRepository>().activer(v),
                          ),
                    title: Text(tr(context, 'vm_set_enable')),
                    subtitle: Text(
                      tr(context, 'vm_set_enable_hint'),
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ),
                  const Divider(height: 1),

                  _entete(tr(context, 'vm_set_absence')),
                  if (etat?.enAbsence == true)
                    ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(
                        tr(context, 'vm_set_absence_until', {
                          'heure': _horodatageCourt(etat!.jusquA!.toLocal()),
                        }),
                      ),
                      trailing: TextButton(
                        onPressed: _envoi
                            ? null
                            : () => _ecrire(
                                () => context
                                    .read<RepondeurRepository>()
                                    .poserAbsence(0),
                              ),
                        child: Text(tr(context, 'vm_set_absence_end')),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in _durees)
                            ActionChip(
                              label: Text(_libelleDuree(m)),
                              onPressed: _envoi
                                  ? null
                                  : () => _ecrire(
                                      () => context
                                          .read<RepondeurRepository>()
                                          .poserAbsence(m),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),

                  _entete(tr(context, 'vm_set_greetings')),
                  if (etat == null || etat.accueils.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Text(
                        tr(context, 'vm_set_none'),
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ),
                  for (final a in etat?.accueils ?? const <Accueil>[])
                    ListTile(
                      leading: IconButton(
                        icon: Icon(
                          _enEcoute == a.id
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        onPressed: () => _ecouter(a),
                      ),
                      title: Text(a.libelle.isEmpty ? a.id : a.libelle),
                      subtitle: a.actif
                          ? Text(
                              tr(context, 'vm_set_used'),
                              style: const TextStyle(fontSize: 12.5),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Choisir celui qu'on entend — absent s'il l'est
                          // déjà : une action sans effet ne doit pas être
                          // proposée.
                          if (!a.actif)
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: _envoi
                                  ? null
                                  : () => _ecrire(
                                      () => context
                                          .read<RepondeurRepository>()
                                          .choisirAccueil(a.id),
                                    ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _envoi
                                ? null
                                : () => _ecrire(
                                    () => context
                                        .read<RepondeurRepository>()
                                        .retirerAccueil(a.id),
                                  ),
                          ),
                        ],
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: FilledButton.icon(
                      onPressed: _envoi ? null : _basculerEnregistrement,
                      icon: Icon(
                        _enregistre ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        _enregistre
                            ? "${tr(context, 'vm_set_recording')}  ·  $_duree"
                            : tr(context, 'vm_set_new'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _entete(String texte) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
    child: Text(
      texte,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}
