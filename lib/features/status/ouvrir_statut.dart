import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/status.dart';
import 'screens/status_viewer_screen.dart';
import 'status_repository.dart';
import 'statuts_en_direct.dart';

/// Ouvrir des statuts depuis AILLEURS que l'onglet Statuts (01/11/2026, repris
/// d'Alanya) : l'anneau d'un avatar dans la liste des discussions, la citation
/// d'un statut dans une conversation.

/// Les statuts de [groupe], depuis l'avatar d'une discussion. Au retour, le
/// fil est rechargé : l'anneau doit passer au gris des statuts vus.
Future<void> ouvrirStatutsDe(BuildContext context, StatusGroup groupe) async {
  final repo = context.read<StatusRepository>();
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => StatusViewerScreen(groups: [groupe], isMine: false),
    ),
  );
  await StatutsEnDirect.instance.charger(repo);
}

/// Le statut cité par une réponse, s'il est encore en ligne.
///
/// Rend `false` s'il a expiré, été supprimé, ou n'est plus visible : la
/// citation garde son instantané, mais le statut vivant n'existe plus.
Future<bool> ouvrirStatutCite(
  BuildContext context, {
  required String statusId,
  required String authorId,
}) async {
  final repo = context.read<StatusRepository>();
  final nav = Navigator.of(context);
  StatusFeed? fil;
  try {
    fil = await repo.feed();
    StatutsEnDirect.instance.retenirFil(fil);
  } catch (_) {
    fil = StatutsEnDirect.instance.fil;
  }
  if (fil == null) return false;
  final maintenant = DateTime.now();
  final moi = fil.me;
  for (final g in [if (moi != null) moi, ...fil.others]) {
    if (g.userId != authorId) continue;
    for (final s in g.statuses) {
      if (s.id != statusId || !s.expiresAt.isAfter(maintenant)) continue;
      // Ce statut-là, et lui seul : c'est de lui que parle la réponse.
      await nav.push(
        MaterialPageRoute(
          builder: (_) => StatusViewerScreen(
            groups: [
              StatusGroup(
                userId: g.userId,
                pseudo: g.pseudo,
                avatarUrl: g.avatarUrl,
                publicNumber: g.publicNumber,
                hasUnviewed: !s.viewed,
                statuses: [s],
              ),
            ],
            isMine: identical(g, moi),
          ),
        ),
      );
      return true;
    }
  }
  return false;
}
