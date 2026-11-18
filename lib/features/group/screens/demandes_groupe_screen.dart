import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/realtime_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/groupe_lien.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../chat/chat_repository.dart';

/// LA LISTE D'ATTENTE D'UN GROUPE PRIVÉ (18/11/2026), pour ses admins.
///
/// Chaque personne qui a ouvert le lien (ou scanné le QR) du groupe y
/// apparaît ; l'admin l'accepte ou la refuse. Le demandeur est prévenu de la
/// réponse par le serveur.
///
/// La liste se relit quand le serveur sonne (`invitation_groupe_demandes` :
/// nouvelle demande, ou demande traitée par un autre admin), pour ne jamais
/// laisser accepter une ligne déjà traitée ailleurs.
class DemandesGroupeScreen extends StatefulWidget {
  const DemandesGroupeScreen({super.key, required this.convId});

  final String convId;

  @override
  State<DemandesGroupeScreen> createState() => _DemandesGroupeScreenState();
}

class _DemandesGroupeScreenState extends State<DemandesGroupeScreen> {
  List<DemandeAdhesion>? _demandes;
  String? _erreur;
  final Set<String> _enCours = {};
  StreamSubscription<Map<String, dynamic>>? _rtSub;

  @override
  void initState() {
    super.initState();
    _charger();
    _rtSub = context.read<RealtimeClient>().events.listen((e) {
      if (e['type'] == 'invitation_groupe_demandes' && e['convId'] == widget.convId) _charger();
    });
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    final repo = context.read<ChatRepository>();
    final echec = trLu(context, 'grp_requests_load_failed');
    try {
      final l = await repo.demandesDuGroupe(widget.convId);
      if (mounted) {
        setState(() {
          _demandes = l;
          _erreur = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _erreur = echec);
    }
  }

  Future<void> _decider(DemandeAdhesion d, bool accepter) async {
    if (_enCours.contains(d.id)) return;
    final repo = context.read<ChatRepository>();
    final nom = d.pseudo.isNotEmpty ? d.pseudo : formatAlanyaId(d.publicNumber);
    final acceptee = trLu(context, 'grp_requests_accepted', {'name': nom});
    final refusee = trLu(context, 'grp_requests_refused');
    final deja = trLu(context, 'grp_requests_already');
    final horsPerimetre = trLu(context, 'grp_requests_out_of_scope');
    final sansCles = trLu(context, 'grp_requests_no_keys');
    final echec = trLu(context, 'grp_requests_failed');
    setState(() => _enCours.add(d.id));
    try {
      await repo.deciderDemandeGroupe(widget.convId, d.id, accepter: accepter);
      showAppSnackBar(accepter ? acceptee : refusee);
    } on ApiException catch (e) {
      showAppSnackBar(switch (e.code) {
        'DEJA_TRAITEE' => deja,
        'HORS_PERIMETRE' => horsPerimetre,
        'CLES_MANQUANTES' => sansCles,
        _ => echec,
      });
    } catch (_) {
      showAppSnackBar(echec);
    } finally {
      if (mounted) setState(() => _enCours.remove(d.id));
      await _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final demandes = _demandes;
    return Scaffold(
      backgroundColor: s.fond,
      appBar: backAppBar(context, tr(context, 'grp_requests_title')),
      body: demandes == null
          ? Center(
              child: _erreur == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erreur!, style: TextStyle(color: dangerOf(context))),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _charger, child: Text(tr(context, 'retry'))),
                      ],
                    ),
            )
          : RefreshIndicator(
              onRefresh: _charger,
              child: demandes.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(Icons.how_to_reg_outlined, size: 48, color: mutedOf(context, Colors.black38)),
                        const SizedBox(height: 12),
                        Text(
                          tr(context, 'grp_requests_none'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: mutedOf(context, Colors.black54)),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: demandes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) => _ligne(demandes[i]),
                    ),
            ),
    );
  }

  Widget _ligne(DemandeAdhesion d) {
    final nom = d.pseudo.isNotEmpty ? d.pseudo : formatAlanyaId(d.publicNumber);
    final occupe = _enCours.contains(d.id);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      leading: AvatarCircle(name: nom, avatarUrl: d.avatarUrl, radius: 22),
      title: Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatAlanyaId(d.publicNumber), style: alanyaIdStyleOf(context)),
      trailing: occupe
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: tr(context, 'grp_requests_refuse'),
                  icon: Icon(Icons.close_rounded, color: dangerOf(context)),
                  onPressed: () => _decider(d, false),
                ),
                IconButton(
                  tooltip: tr(context, 'grp_requests_accept'),
                  icon: Icon(Icons.check_rounded, color: accentOf(context)),
                  onPressed: () => _decider(d, true),
                ),
              ],
            ),
    );
  }
}
