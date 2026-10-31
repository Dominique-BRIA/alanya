import 'package:flutter/foundation.dart';

import '../../models/status.dart';
import 'status_repository.dart';

/// Les statuts que TOUTE l'application partage (01/11/2026).
///
/// Deux besoins l'ont fait naître :
///
/// - **la liste des discussions** dessine un anneau autour de l'avatar d'un
///   contact qui a des statuts (repris d'Alanya) ; or le fil des statuts vivait
///   dans l'onglet Statuts, que l'onglet Discussions ne voyait pas ;
/// - **les vues et les « J'aime » arrivent en direct** (`statut_vu`,
///   `statut_aime`) : l'auteur voit ses compteurs bouger sans rouvrir la
///   liste. Les compteurs reçus passent devant ceux du dernier fil chargé.
class StatutsEnDirect extends ChangeNotifier {
  StatutsEnDirect._();
  static final instance = StatutsEnDirect._();

  StatusFeed? _fil;
  StatusFeed? get fil => _fil;

  final _vues = <String, int>{};
  final _aimes = <String, int>{};
  final _aimeParMoi = <String, bool>{};

  /// Retient le dernier fil chargé. Les compteurs reçus en direct repartent
  /// de lui : il est plus récent qu'eux.
  void retenirFil(StatusFeed fil) {
    _fil = fil;
    _vues.clear();
    _aimes.clear();
    _aimeParMoi.clear();
    notifyListeners();
  }

  /// Charge le fil s'il n'est pas encore connu — la copie du téléphone
  /// d'abord, le réseau ensuite.
  Future<void> charger(StatusRepository repo) async {
    if (_fil == null) {
      final copie = await repo.feedEnCache();
      if (copie != null && _fil == null) retenirFil(copie);
    }
    try {
      retenirFil(await repo.feed());
    } catch (_) {
      // Hors ligne : la copie (ou rien) suffit à dessiner les anneaux.
    }
  }

  /// Les statuts d'un contact, s'il en a d'actifs.
  StatusGroup? groupeDe(String? userId) {
    if (userId == null) return null;
    for (final g in _fil?.others ?? const <StatusGroup>[]) {
      if (g.userId == userId) {
        final restants = [
          for (final s in g.statuses)
            if (s.expiresAt.isAfter(DateTime.now())) s,
        ];
        return restants.isEmpty
            ? null
            : StatusGroup(
                userId: g.userId,
                pseudo: g.pseudo,
                avatarUrl: g.avatarUrl,
                publicNumber: g.publicNumber,
                hasUnviewed: restants.any((s) => !s.viewed),
                statuses: restants,
              );
      }
    }
    return null;
  }

  int vues(StatusItem s) => _vues[s.id] ?? s.viewsCount;
  int aimes(StatusItem s) => _aimes[s.id] ?? s.likesCount ?? 0;
  bool aimeParMoi(StatusItem s) => _aimeParMoi[s.id] ?? s.likedByMe;

  /// Mon « J'aime » vient de changer, avant même la réponse du serveur.
  void marquerAime(String statusId, bool aime) {
    _aimeParMoi[statusId] = aime;
    notifyListeners();
  }

  /// Un événement du serveur temps réel (`statut_vu`, `statut_aime`).
  void recevoir(Map<String, dynamic> e) {
    final id = e["statusId"];
    if (id is! String) return;
    switch (e["type"]) {
      case "statut_vu":
        final n = e["viewsCount"];
        if (n is num) _vues[id] = n.toInt();
        break;
      case "statut_aime":
        final n = e["likesCount"];
        if (n is num) _aimes[id] = n.toInt();
        break;
      default:
        return;
    }
    notifyListeners();
  }
}
