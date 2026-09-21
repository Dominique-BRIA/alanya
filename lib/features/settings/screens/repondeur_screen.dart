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
  List<PlageRepondeur> _plages = const [];

  /// Redessine quand l'heure fait entrer ou sortir d'une plage.
  ///
  /// 🐛 LE REPÈRE « EN COURS » N'APPARAISSAIT JAMAIS SUR LES PLAGES. Le calcul
  /// était juste, mais RIEN ne le relançait : un écran ouvert à 9 h 59 devant
  /// une plage de 10 h à 12 h restait sur son affichage de 9 h 59. Flutter ne
  /// redessine que sur `setState`, et le temps qui passe n'en est pas un.
  ///
  /// ⚠️ ON NE REDESSINE QUE SI LA RÉPONSE A CHANGÉ. Un `setState` toutes les
  /// vingt secondes pour un écran identique userait la batterie pour rien —
  /// et cet écran-ci reste ouvert le temps qu'on enregistre un message.
  Timer? _horloge;
  bool _plageEtaitEnCours = false;

  /// Les durées proposées, en minutes. La dernière est la borne du serveur :
  /// au-delà, ce n'est plus une absence mais un compte injoignable.
  static const _durees = <int>[30, 60, 120, 240, 480, absenceMaxMinutes];

  @override
  void initState() {
    super.initState();
    _horloge = Timer.periodic(const Duration(seconds: 20), (_) {
      final ici = _plageEnCours;
      if (ici != _plageEtaitEnCours && mounted) {
        setState(() => _plageEtaitEnCours = ici);
      }
    });
    _charger();
  }

  @override
  void dispose() {
    _tic?.cancel();
    _horloge?.cancel();
    unawaited(RingtoneService.instance.stop());
    if (_enregistreur.enCours) unawaited(_enregistreur.stop());
    super.dispose();
  }

  Future<void> _charger() async {
    final depot = context.read<RepondeurRepository>();
    try {
      /*
       * ⚠️ LES DEUX LECTURES EN PARALLÈLE, ET NON L'UNE APRÈS L'AUTRE : elles
       * ne dépendent pas l'une de l'autre, et les enchaîner doublerait l'attente
       * sur un réseau mobile pour rien.
       */
      final (etat, plages) = await (depot.lire(), depot.listerPlages()).wait;
      if (!mounted) return;
      setState(() {
        _etat = etat;
        _plages = plages;
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


  /// Exécute une écriture de plages et adopte la liste rendue par le serveur.
  ///
  /// 🔴 UN REFUS NE VEUT PAS DIRE QUE RIEN N'A ÉTÉ ENREGISTRÉ. Le serveur range
  /// les plages D'ABORD, puis refuse d'allumer le répondeur s'il n'y a aucun
  /// message d'accueil (`NO_GREETING`) : la programmation est bien là, seul
  /// l'allumage manque. Repartir sans relire laisserait l'écran prétendre que la
  /// plage n'existe pas, et la personne la saisirait une seconde fois.
  Future<void> _ecrirePlages(
    Future<List<PlageRepondeur>> Function() action,
  ) async {
    setState(() => _envoi = true);
    try {
      final plages = await action();
      if (!mounted) return;
      setState(() {
        _plages = plages;
        _envoi = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      showAppSnackBar(e.message);
      // Voir ci-dessus : on relit, le refus ne dit rien de ce qui a été rangé.
      await _relirePlages();
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      showAppSnackBar(tr(context, 'save_failed_short'));
    }
  }

  Future<void> _relirePlages() async {
    try {
      final plages = await context.read<RepondeurRepository>().listerPlages();
      if (mounted) setState(() => _plages = plages);
    } catch (_) {
      // Relecture de confort : son échec ne doit rien casser.
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
      // Même raison que dans la feuille de l'appelant : un aperçu qui se termine
      // doit rendre son bouton, sans quoi il faut deux appuis pour le relancer.
      onFin: () {
        if (mounted) setState(() => _enEcoute = null);
      },
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
      if (!mounted) return;
      /*
       * ⚠️ ON S'ARRÊTE SEUL À [accueilMaxMs], comme le fait le web.
       *
       * Sans cette coupure, rien n'arrêtait l'enregistrement : ni l'écran, ni
       * le serveur, qui ne contrôle que le type du fichier. Un accueil de dix
       * minutes partait donc en entier — la donnée est payée — et se jouait
       * ensuite à chaque appelant.
       *
       * On termine plutôt que d'annuler : la personne a parlé, sa voix est
       * enregistrée, et jeter les trente secondes obtenues pour la punir d'avoir
       * continué serait le contraire d'un service.
       */
      if (_enregistreur.duree.inMilliseconds >= accueilMaxMs) {
        _terminerAccueil();
        return;
      }
      setState(() {});
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

    /*
     * ⚠️ LE POIDS EST CONTRÔLÉ AVANT L'ENVOI, pas après. Un fichier trop lourd
     * partirait sinon EN ENTIER pour se faire refuser à l'arrivée — et la donnée
     * est payée, sur mobile plus qu'ailleurs.
     *
     * La borne de 30 s rend ce cas rare, mais elle ne le rend pas impossible :
     * elle arrête le MINUTEUR, pas l'encodeur, et un appareil qui capture en
     * haute qualité peut dépasser. Deux gardes valent mieux qu'une supposition.
     */
    if (capture.bytes.length > accueilMaxOctets) {
      showAppSnackBar(tr(context, 'vm_too_heavy'));
      return;
    }

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


    final enAbsence = etat?.enAbsence == true;
    final plageActive = _plageEnCours;

    /*
     * ⚠️ LE MÊME FOND QUE L'ÉCRAN RÉUNIONS (demande user 21/09/2026).
     *
     * Une couleur unie avait été posée ici, décidée en thème Clair seulement.
     * Deux défauts : l'écran ne ressemblait plus au reste de l'application, et
     * en thème BLANC la condition retombait sur le fond de ce thème — d'où un
     * écran franchement blanc là où on attendait une teinte.
     *
     * `MotifBackground` règle les deux d'un coup : c'est lui que portent les
     * autres écrans, et il sait déjà quoi faire dans les quatre thèmes.
     */
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
                          () => context.read<RepondeurRepository>().activer(v),
                        ),
                  title: Text(tr(context, 'vm_set_enable')),
                  subtitle: Text(
                    tr(context, 'vm_set_enable_hint'),
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ),
                const Divider(height: 1),

                /*
                 * 🔴 LES TROIS CAS SONT DES ENTRÉES, PAS DES PARAGRAPHES.
                 *
                 * Ils s'affichaient en trois lignes alignées dont une portait
                 * un repère « en cours » : on y lisait trois choix exclusifs,
                 * ce qu'ils ne sont pas, et surtout trois boutons — alors que
                 * rien n'était cliquable. Pour poser une absence il fallait
                 * descendre vers une SECONDE section du même nom, plus bas.
                 *
                 * Chaque entrée ouvre maintenant ses propres réglages, et le
                 * mot « Absence » n'apparaît plus qu'une seule fois à l'écran.
                 *
                 * ⚠️ « SONNERIE D'ABORD » N'OUVRE RIEN, et c'est voulu : ce
                 * n'est pas un réglage, c'est ce qui se passe quand aucune
                 * exception ne court. Elle devient cliquable UNIQUEMENT quand
                 * une absence peut être levée — un appui qui ne fait rien vaut
                 * moins qu'une ligne qui n'invite pas à appuyer.
                 */
                _option(
                  icone: Icons.notifications_active_outlined,
                  titre: tr(context, 'vm_mode_ring'),
                  detail: enAbsence
                      ? tr(context, 'vm_mode_ring_back')
                      : tr(context, 'vm_mode_ring_d'),
                  enCours: (etat?.actif ?? false) && !enAbsence && !plageActive,
                  muted: muted,
                  onTap: enAbsence && !_envoi
                      ? () => _ecrire(
                          () => context
                              .read<RepondeurRepository>()
                              .poserAbsence(0),
                        )
                      : null,
                ),
                _option(
                  icone: Icons.schedule_rounded,
                  titre: tr(context, 'vm_set_absence'),
                  detail: enAbsence
                      ? tr(context, 'vm_set_absence_until', {
                          'heure': _horodatageCourt(etat!.jusquA!.toLocal()),
                        })
                      : tr(context, 'vm_mode_absence_d'),
                  enCours: enAbsence,
                  muted: muted,
                  onTap: _envoi ? null : _ouvrirAbsence,
                ),
                _option(
                  icone: Icons.event_repeat_rounded,
                  titre: tr(context, 'vm_prog_title'),
                  detail: _plages.isEmpty
                      ? tr(context, 'vm_mode_prog_d')
                      : tr(context, 'vm_prog_count')
                            .replaceAll('{n}', '${_plages.length}'),
                  enCours: !enAbsence && plageActive,
                  muted: muted,
                  onTap: _envoi ? null : _ouvrirPlages,
                ),
                const Divider(height: 1),

                _entete(tr(context, 'vm_set_greetings')),
                if (etat == null || etat.accueils.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      tr(context, 'vm_set_none'),
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: muted),
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
                        // Choisir celui qu'on entend — absent s'il l'est déjà :
                        // une action sans effet ne doit pas être proposée.
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

  /// « Lundi · 10:00 – 12:00 », dans la langue et le format de l'appareil.
  String _libellePlage(PlageRepondeur plage) {
    final loc = MaterialLocalizations.of(context);
    /*
     * ⚠️ `narrowWeekdays` COMMENCE À DIMANCHE — c'est écrit dans son contrat —
     * et c'est exactement la convention du serveur (`jour` : 0 = dimanche).
     * Les deux coïncident, il n'y a donc RIEN à décaler ici.
     *
     * ⚠️ NE PAS PASSER PAR `DateTime.weekday`, qui compte 1 = lundi … 7 =
     * dimanche. Les deux conventions se ressemblent assez pour qu'on les
     * confonde, et assez peu pour que tout se décale d'un jour.
     */
    final jour = loc.narrowWeekdays[plage.jour % 7];
    final base = '$jour · ${_heure(plage.debutMin)} – ${_heure(plage.finMin)}';
    /*
     * ⚠️ L'ACCUEIL PROPRE À LA PLAGE SE VOIT, sans quoi on ne saurait plus
     * lequel on a choisi — et le choix, fait une fois dans une feuille qui se
     * referme, ne serait plus vérifiable nulle part.
     *
     * Rien n'est ajouté quand la plage suit l'accueil actif : c'est le cas
     * courant, et l'annoncer à chaque ligne ferait du bruit pour rien.
     */
    final id = plage.accueilId;
    if (id == null || id.isEmpty) return base;
    // L'accueil a pu être supprimé depuis : on ne montre que ce qu'on retrouve.
    for (final a in _etat?.accueils ?? const <Accueil>[]) {
      if (a.id == id) {
        return a.libelle.isEmpty ? base : '$base · ${a.libelle}';
      }
    }
    return base;
  }

  /// Des minutes depuis minuit vers l'heure telle que l'appareil l'écrit.
  String _heure(int minutes) => MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60),
    // Le format 24 h suit le réglage du téléphone, et non une préférence à nous.
    alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
  );

  String _dateCourte(DateTime? d) => d == null
      ? ''
      : MaterialLocalizations.of(context).formatShortDate(d.toLocal());

  /// La feuille de saisie : des jours, une heure de début, une heure de fin.
  ///
  /// ⚠️ PLUSIEURS JOURS D'UN COUP, et c'est ce que la route attend : elle
  /// accepte un tableau. « Du lundi au vendredi, 12 h-14 h » se pose donc en une
  /// fois, au lieu de cinq saisies identiques dont la quatrième se trompe.
  Future<void> _ajouterPlage() async {
    final loc = MaterialLocalizations.of(context);
    final jours = <int>{};
    var debut = const TimeOfDay(hour: 9, minute: 0);
    var fin = const TimeOfDay(hour: 12, minute: 0);
    /*
     * L'accueil PROPRE à cette plage. `null` = celui qui sera actif ce jour-là,
     * et c'est le cas courant : on ne veut pas choisir à chaque fois.
     *
     * ⚠️ LE CHOIX N'APPARAÎT QU'À PARTIR DE DEUX ACCUEILS. Proposer de choisir
     * quand il n'y en a qu'un donnerait une liste à une entrée, dont l'effet
     * serait strictement nul — et un réglage dont on ne peut rien faire se lit
     * comme un réglage cassé.
     */
    String? accueilPlage;
    final accueils = _etat?.accueils ?? const <Accueil>[];

    final valide = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (feuille) => StatefulBuilder(
        builder: (feuille, redessine) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(feuille).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(feuille, 'vm_prog_days'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  /*
                   * L'ordre d'AFFICHAGE suit la locale — lundi d'abord en
                   * France, dimanche aux États-Unis — pendant que la VALEUR
                   * envoyée reste celle du serveur. `firstDayOfWeekIndex` existe
                   * pour ça, et se lit dans `narrowWeekdays`.
                   */
                  for (var d = 0; d < 7; d++)
                    () {
                      final jour = (loc.firstDayOfWeekIndex + d) % 7;
                      return FilterChip(
                        label: Text(loc.narrowWeekdays[jour]),
                        selected: jours.contains(jour),
                        onSelected: (pris) => redessine(
                          () => pris ? jours.add(jour) : jours.remove(jour),
                        ),
                      );
                    }(),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final choix = await showTimePicker(
                          context: feuille,
                          initialTime: debut,
                        );
                        if (choix != null) redessine(() => debut = choix);
                      },
                      child: Text(
                        '${tr(feuille, 'vm_prog_from')} ${loc.formatTimeOfDay(debut)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final choix = await showTimePicker(
                          context: feuille,
                          initialTime: fin,
                        );
                        if (choix != null) redessine(() => fin = choix);
                      },
                      child: Text(
                        '${tr(feuille, 'vm_prog_to')} ${loc.formatTimeOfDay(fin)}',
                      ),
                    ),
                  ),
                ],
              ),
              if (accueils.length > 1) ...[
                const SizedBox(height: 16),
                Text(
                  tr(feuille, 'vm_prog_greeting'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                DropdownButton<String?>(
                  isExpanded: true,
                  value: accueilPlage,
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(tr(feuille, 'vm_prog_greeting_default')),
                    ),
                    for (final a in accueils)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text(
                          a.libelle.isEmpty
                              ? tr(feuille, 'vm_set_none')
                              : a.libelle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => redessine(() => accueilPlage = v),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(feuille).pop(true),
                  child: Text(tr(feuille, 'ok')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (valide != true || !mounted) return;
    if (jours.isEmpty) {
      showAppSnackBar(tr(context, 'vm_prog_day_required'));
      return;
    }

    final debutMin = debut.hour * 60 + debut.minute;
    final finMin = fin.hour * 60 + fin.minute;
    /*
     * ⚠️ REFUSÉ ICI AUSSI, et pas seulement par la route. Une plage qui finit
     * avant de commencer ne s'ouvrirait jamais ; le serveur la refuse, mais son
     * refus arriverait après l'aller-retour, alors que l'écran sait déjà.
     *
     * ⚠️ ET AVEC SON PROPRE MESSAGE. Réutiliser « choisissez au moins un jour »
     * aurait coûté une clé de moins et envoyé la personne vérifier ses jours,
     * qui n'ont rien à voir avec le problème.
     */
    if (finMin <= debutMin) {
      showAppSnackBar(tr(context, 'vm_prog_order'));
      return;
    }

    await _ecrirePlages(
      () => context.read<RepondeurRepository>().ajouterPlages([
        for (final j in jours)
          {
            'jour': j,
            'debutMin': debutMin,
            'finMin': finMin,
            // Omis quand il est nul : la route lit `accueilId` comme facultatif,
            // et une clé à `null` n'apporte rien de plus qu'une clé absente.
            if (accueilPlage != null) 'accueilId': accueilPlage,
          },
      ]),
    );
    if (mounted) showAppSnackBar(tr(context, 'vm_prog_saved'));
  }
  /// Une plage couvre-t-elle CET instant ?
  ///
  /// ⚠️ C'EST UN REFLET D'AFFICHAGE, PAS LA RÈGLE. La règle vit dans
  /// `lib/repondeur.mjs` côté serveur, qui la pose dans le fuseau de la plage —
  /// et c'est lui qui décide pour de bon. Ici on se contente de l'heure locale :
  /// l'écran montre à son propriétaire ce qui s'applique chez LUI, et le fuseau
  /// d'une plage qu'il vient de poser est justement le sien.
  ///
  /// ⚠️ UNE PLAGE PÉRIMÉE NE COMPTE PAS, comme côté serveur : elle cesse de
  /// répondre « oui » au bout de deux semaines, sans qu'aucune tâche n'ait eu à
  /// tourner.
  bool get _plageEnCours {
    final maintenant = DateTime.now();
    // `DateTime.weekday` compte 1 = lundi … 7 = dimanche ; le serveur compte
    // 0 = dimanche. `% 7` fait exactement la conversion.
    final jour = maintenant.weekday % 7;
    final minutes = maintenant.hour * 60 + maintenant.minute;
    return _plages.any(
      (p) =>
          !p.expiree &&
          p.jour == jour &&
          // Début inclus, fin EXCLUE — sans quoi deux plages qui se touchent
          // se disputeraient la minute de bascule.
          minutes >= p.debutMin &&
          minutes < p.finMin,
    );
  }

  /// Une entrée de la liste des trois cas.
  ///
  /// [enCours] pose le repère : il ne se met que sur UN seul des trois, dans
  /// l'ordre de priorité du serveur — absence, puis plage, puis sonnerie.
  ///
  /// [onTap] nul = la ligne informe sans inviter à appuyer. C'est le cas de
  /// « Sonnerie d'abord » quand il n'y a pas d'absence à lever : elle n'a rien
  /// à régler, et un chevron qui ne mène nulle part est pire qu'une ligne sobre.
  Widget _option({
    required IconData icone,
    required String titre,
    required String detail,
    required bool enCours,
    required Color muted,
    VoidCallback? onTap,
  }) => ListTile(
    onTap: onTap,
    leading: Icon(icone, color: enCours ? null : muted),
    title: Row(
      children: [
        Flexible(child: Text(titre)),
        if (enCours) ...[
          const SizedBox(width: 8),
          // Un repère discret plutôt qu'une couleur d'alerte : ce n'est pas un
          // avertissement, c'est la réponse à « lequel s'applique ? ».
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr(context, 'vm_mode_now'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    ),
    subtitle: Text(detail, style: TextStyle(fontSize: 12, color: muted)),
    trailing: onTap == null
        ? null
        : Icon(Icons.chevron_right_rounded, color: muted),
  );

  /// Les réglages de l'absence, là où on appuie sur « Absence ».
  ///
  /// ⚠️ LA FEUILLE SE FERME AVANT D'ÉCRIRE, et non après : `_ecrire` pose
  /// `_envoi`, qui grise l'écran DERRIÈRE la feuille. Attendre la réponse la
  /// laisserait ouverte au-dessus d'un écran inerte, sans rien indiquer.
  Future<void> _ouvrirAbsence() async {
    final enCours = _etat?.enAbsence == true;
    final choix = await showModalBottomSheet<int>(
      context: context,
      builder: (feuille) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                tr(feuille, 'vm_set_absence'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                tr(feuille, 'vm_mode_absence_d'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: mutedOf(feuille, Colors.black54),
                ),
              ),
            ),
            if (enCours)
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: Text(
                  tr(feuille, 'vm_set_absence_until', {
                    'heure': _horodatageCourt(_etat!.jusquA!.toLocal()),
                  }),
                ),
                trailing: TextButton(
                  // 0 lève l'absence — c'est le serveur qui en décide, on ne
                  // fait que transmettre la durée.
                  onPressed: () => Navigator.of(feuille).pop(0),
                  child: Text(tr(feuille, 'vm_set_absence_end')),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _durees)
                      ActionChip(
                        label: Text(_libelleDuree(m)),
                        onPressed: () => Navigator.of(feuille).pop(m),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (choix == null || !mounted) return;
    await _ecrire(
      () => context.read<RepondeurRepository>().poserAbsence(choix),
    );
  }

  /// Les plages programmées, là où on appuie sur « Plages programmées ».
  ///
  /// ⚠️ LA FEUILLE SE REDESSINE SUR `_plages`, qui vit dans l'écran : ajouter
  /// ou retirer une plage doit se voir SANS refermer. D'où le `StatefulBuilder`
  /// et le `redessine` posé après chaque écriture.
  Future<void> _ouvrirPlages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (feuille) => StatefulBuilder(
        builder: (feuille, redessine) {
          final muted = mutedOf(feuille, Colors.black54);
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                    child: Text(
                      tr(feuille, 'vm_prog_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      tr(feuille, 'vm_prog_sub'),
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ),
                  if (_plages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                      child: Text(
                        tr(feuille, 'vm_prog_none'),
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    )
                  else
                    for (final plage in _plages)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.event_repeat_rounded,
                          // Une plage périmée ne s'applique plus : elle reste
                          // lisible, sans se présenter comme active.
                          color: plage.expiree ? muted : null,
                        ),
                        title: Text(_libellePlage(plage)),
                        subtitle: Text(
                          plage.expiree
                              ? tr(feuille, 'vm_prog_expired')
                              : tr(feuille, 'vm_prog_expires').replaceAll(
                                  '{date}',
                                  _dateCourte(plage.expireLe),
                                ),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: _envoi
                              ? null
                              : () async {
                                  await _ecrirePlages(
                                    () => context
                                        .read<RepondeurRepository>()
                                        .retirerPlage(plage.id),
                                  );
                                  redessine(() {});
                                },
                        ),
                      ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: OutlinedButton.icon(
                      // La borne du serveur est ici aussi : atteindre 40 plages
                      // et se voir refuser la 41e après l'avoir saisie serait un
                      // aller-retour pour rien.
                      onPressed: _envoi || _plages.length >= plagesMax
                          ? null
                          : () async {
                              await _ajouterPlage();
                              redessine(() {});
                            },
                      icon: const Icon(Icons.add_rounded),
                      label: Text(tr(feuille, 'vm_prog_add')),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                    child: Text(
                      tr(feuille, 'vm_prog_validity'),
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
