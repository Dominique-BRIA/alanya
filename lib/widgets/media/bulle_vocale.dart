import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio_player.dart';
import '../../core/formes_onde.dart';
import 'forme_onde_vocale.dart';

/// LA bulle d'un message vocal, en clair comme chiffré (18/10/2026).
///
/// 🐛 « J'ENVOIE UN VOCAL, REGARDE COMMENT ÇA SE PRÉSENTE : CE N'EST PAS BEAU.
/// AVANT, IL Y AVAIT UN TRAIT AU MILIEU » (patron). Dans un fil chiffré — le
/// cas par défaut —, un vocal n'était qu'une icône, « Message vocal » et sa
/// durée ; en clair, 28 barres au même motif pour tous les messages.
///
/// Désormais, comme Talky (`VoiceMessageBubble`) :
/// * la VRAIE forme d'onde du message (`FormesOnde`), des barres stables en
///   attendant ;
/// * la partie écoutée qui se remplit, et un toucher sur l'onde pour avancer ;
/// * « 0:12 / 0:45 » pendant l'écoute, la durée seule sinon ;
/// * la vitesse 1× → 1,5× → 2×, gardée d'un vocal à l'autre.
///
/// ⚠️ UN SEUL LECTEUR POUR TOUTE L'APPLICATION (`InlineAudioPlayer`) : lancer
/// un vocal arrête le précédent, en clair comme chiffré.
class BulleVocale extends StatefulWidget {
  const BulleVocale({
    super.key,
    required this.identite,
    required this.obtenirSource,
    required this.isMe,
    required this.couleur,
    required this.couleurDiscrete,
    this.duree,
    this.chargementAuto = true,
    this.onLongPress,
    this.pied,
  });

  /// Stable pour CE message (son identifiant) : graine des barres d'attente.
  final String identite;

  /// Ce que le lecteur doit jouer — une adresse, ou un fichier du téléphone
  /// (un vocal chiffré se déchiffre ici). `null` : indisponible.
  final Future<String?> Function() obtenirSource;

  final bool isMe;
  final Color couleur;
  final Color couleurDiscrete;
  final Duration? duree;

  /// Préparer le fichier dès l'affichage, pour montrer sa vraie forme d'onde.
  /// Faux pour un gros fichier : on attend le premier toucher.
  final bool chargementAuto;
  final VoidCallback? onLongPress;

  /// Sous la bulle : l'heure et les coches, par exemple.
  final Widget? pied;

  @override
  State<BulleVocale> createState() => _BulleVocaleState();
}

class _BulleVocaleState extends State<BulleVocale> {
  String? _source;
  bool _preparation = false;
  bool _indisponible = false;
  late List<double> _barres = formeOndeDeRepli(
      widget.identite, widget.duree?.inSeconds ?? 0);

  @override
  void initState() {
    super.initState();
    if (widget.chargementAuto) unawaited(_preparer());
  }

  /// Rend la source jouable, et en tire la vraie forme d'onde.
  Future<String?> _preparer() async {
    if (_source != null) return _source;
    if (_preparation) return null;
    setState(() => _preparation = true);
    String? source;
    try {
      source = await widget.obtenirSource();
    } catch (_) {
      source = null;
    }
    if (!mounted) return source;
    setState(() {
      _source = source;
      _preparation = false;
      _indisponible = source == null;
    });
    if (source != null) unawaited(_lireForme(source));
    return source;
  }

  Future<void> _lireForme(String source) async {
    final local = await InlineAudioPlayer.fichierLocal(source);
    if (local == null) return;
    final barres = await FormesOnde.pour(
        cheminLocal: local, dureeSecondes: widget.duree?.inSeconds ?? 0);
    if (mounted) setState(() => _barres = barres);
  }

  Future<void> _basculer() async {
    final source = _source ?? await _preparer();
    if (source == null) return;
    await InlineAudioPlayer.toggle(source, totalDuration: widget.duree);
  }

  Future<void> _avancer(double ratio, Duration total) async {
    final source = _source ?? await _preparer();
    if (source == null || total == Duration.zero) return;
    final cible = Duration(milliseconds: (total.inMilliseconds * ratio).round());
    if (InlineAudioPlayer.state.value.url != source) {
      await InlineAudioPlayer.play(source, totalDuration: widget.duree);
    }
    await InlineAudioPlayer.seek(cible);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: ValueListenableBuilder<AudioPlaybackState>(
        valueListenable: InlineAudioPlayer.state,
        builder: (context, etat, _) {
          final actif = _source != null && etat.url == _source;
          final joue = actif && etat.isPlaying;
          final total = (actif ? etat.duration : null) ??
              widget.duree ??
              Duration.zero;
          final position = actif ? etat.position : Duration.zero;
          final ratio = total.inMilliseconds == 0
              ? 0.0
              : (position.inMilliseconds / total.inMilliseconds)
                  .clamp(0.0, 1.0)
                  .toDouble();
          final commence = actif && (joue || position > Duration.zero);
          final temps = commence
              ? '${_fmt(position)} / ${_fmt(total)}'
              : (total == Duration.zero ? '' : _fmt(total));

          return ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _bouton(joue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FormeOndeVocale(
                            barres: _barres,
                            progression: ratio,
                            couleur: widget.couleur,
                            onAvance: _indisponible
                                ? null
                                : (r) => _avancer(r, total),
                          ),
                          const SizedBox(height: 2),
                          Row(children: [
                            Text(temps,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: widget.couleurDiscrete)),
                            const Spacer(),
                            // La vitesse, quand ce vocal est celui qui joue :
                            // c'est là qu'on la cherche.
                            if (actif) _Vitesse(couleur: widget.couleur),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.pied != null) ...[
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerRight, child: widget.pied!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bouton(bool joue) {
    if (_preparation && _source == null) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: widget.couleur),
          ),
        ),
      );
    }
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(
        _indisponible
            ? Icons.refresh_rounded
            : (joue ? Icons.pause_circle_filled : Icons.play_circle_fill),
        color: widget.couleur,
        size: 36,
      ),
      onPressed: _indisponible
          ? () {
              setState(() => _indisponible = false);
              _preparer();
            }
          : _basculer,
    );
  }
}

/// La pastille 1× → 1,5× → 2×.
class _Vitesse extends StatelessWidget {
  const _Vitesse({required this.couleur});

  final Color couleur;

  String _texte(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}×' : '${v.toString().replaceAll('.', ',')}×';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: InlineAudioPlayer.vitesse,
      builder: (context, v, _) => Material(
        color: couleur.withAlpha(38),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: InlineAudioPlayer.changerVitesse,
          child: Container(
            height: 20,
            constraints: const BoxConstraints(minWidth: 32),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(_texte(v),
                style: TextStyle(
                    fontSize: 11,
                    color: couleur,
                    fontWeight: FontWeight.w600,
                    height: 1.1)),
          ),
        ),
      ),
    );
  }
}
