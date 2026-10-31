import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/groupe_reglages.dart';
import '../chat_repository.dart';

/// LA SOURDINE D'UNE CONVERSATION (01/11/2026, repris d'Alanya2026) : 8 heures,
/// une semaine ou toujours — et, en groupe, « mentions seulement ».
///
/// [onChange] reçoit l'état RETENU PAR LE SERVEUR, jamais celui qu'on
/// espérait — à CHAQUE changement : basculer « mentions seulement » laisse la
/// feuille ouverte, et on peut la fermer d'un geste sans rien rendre.
class FeuilleSourdine {
  FeuilleSourdine._();

  static Future<void> ouvrir(
    BuildContext context, {
    required String convId,
    required bool enGroupe,
    required EtatSourdine actuel,
    required ValueChanged<EtatSourdine> onChange,
  }) {
    final repo = context.read<ChatRepository>();
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _Feuille(
          repo: repo, convId: convId, enGroupe: enGroupe, actuel: actuel, onChange: onChange),
    );
  }
}

class _Feuille extends StatefulWidget {
  const _Feuille({
    required this.repo,
    required this.convId,
    required this.enGroupe,
    required this.actuel,
    required this.onChange,
  });

  final ChatRepository repo;
  final String convId;
  final bool enGroupe;
  final EtatSourdine actuel;
  final ValueChanged<EtatSourdine> onChange;

  @override
  State<_Feuille> createState() => _FeuilleState();
}

class _FeuilleState extends State<_Feuille> {
  late EtatSourdine _etat = widget.actuel;
  bool _envoi = false;

  Future<void> _appliquer({bool? sourdine, Duration? pour, bool? mentionsSeulement, bool fermer = true}) async {
    if (_envoi) return;
    setState(() => _envoi = true);
    try {
      final etat = await widget.repo.definirSourdineDetail(
        widget.convId,
        sourdine: sourdine,
        jusqua: pour == null ? null : DateTime.now().add(pour),
        mentionsSeulement: mentionsSeulement,
      );
      widget.onChange(etat);
      if (!mounted) return;
      if (fermer) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _etat = etat;
          _envoi = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'grp_settings_failed'))),
      );
    }
  }

  String _heure(DateTime d) {
    final l = MaterialLocalizations.of(context);
    final aujourdhui = DateUtils.isSameDay(d, DateTime.now());
    final heure = l.formatTimeOfDay(TimeOfDay.fromDateTime(d));
    return aujourdhui ? heure : '${l.formatShortDate(d)} $heure';
  }

  @override
  Widget build(BuildContext context) {
    final e = _etat;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(tr(context, 'mute_title'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        if (e.sourdine)
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(tr(context, 'unmute')),
            subtitle: e.jusqua == null
                ? null
                : Text(tr(context, 'muted_until', {'quand': _heure(e.jusqua!)})),
            onTap: () => _appliquer(sourdine: false),
          )
        else ...[
          ListTile(
            leading: const Icon(Icons.notifications_paused_outlined),
            title: Text(tr(context, 'mute_8h')),
            onTap: () => _appliquer(pour: const Duration(hours: 8)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_paused_outlined),
            title: Text(tr(context, 'mute_1w')),
            onTap: () => _appliquer(pour: const Duration(days: 7)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(tr(context, 'mute_always')),
            onTap: () => _appliquer(sourdine: true),
          ),
        ],
        // En groupe seulement : à deux, toute la conversation me concerne.
        if (widget.enGroupe)
          SwitchListTile(
            secondary: const Icon(Icons.alternate_email_rounded),
            title: Text(tr(context, 'mute_mentions_only')),
            subtitle: Text(tr(context, 'mute_mentions_only_sub')),
            value: e.mentionsSeulement,
            onChanged: _envoi ? null : (v) => _appliquer(mentionsSeulement: v, fermer: false),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
