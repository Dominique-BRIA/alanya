/// LE GROUPE LUI-MÊME (01/11/2026, repris d'Alanya2026) : sa description, son
/// propriétaire, ses réglages — et ce qui me concerne, la bannière « Rester /
/// Quitter ». Rendu par `GET /api/conversations/:id/members`, à côté de la
/// liste des membres.
///
/// ⚠️ LES VALEURS PAR DÉFAUT SONT LE FONCTIONNEMENT D'AVANT : un serveur qui ne
/// les envoie pas laisse l'écran se comporter comme hier — seuls les admins
/// modifient et ajoutent, tout le monde écrit.
class ReglagesGroupe {
  const ReglagesGroupe({
    this.description,
    this.proprietaireId,
    this.adminsSeulsEcrivent = false,
    this.adminsSeulsModifient = true,
    this.adminsSeulsAjoutent = true,
    this.historiqueCacheNouveaux = false,
    this.arriveeAConfirmer = false,
  });

  final String? description;

  /// Le propriétaire : il garde le rôle ADMIN ; personne ne le retire ni ne
  /// le rétrograde, lui seul change les rôles. `null` = groupe d'avant, sans
  /// propriétaire : les règles d'avant s'appliquent.
  final String? proprietaireId;

  final bool adminsSeulsEcrivent;
  final bool adminsSeulsModifient;
  final bool adminsSeulsAjoutent;
  final bool historiqueCacheNouveaux;

  /// Ajouté par quelqu'un, je n'ai pas encore dit « Rester ».
  final bool arriveeAConfirmer;

  factory ReglagesGroupe.fromJson(Map<String, dynamic>? groupe, Map<String, dynamic>? moi) {
    final g = groupe ?? const {};
    return ReglagesGroupe(
      description: g['description'] as String?,
      proprietaireId: g['proprietaireId'] as String?,
      adminsSeulsEcrivent: (g['adminsSeulsEcrivent'] as bool?) ?? false,
      adminsSeulsModifient: (g['adminsSeulsModifient'] as bool?) ?? true,
      adminsSeulsAjoutent: (g['adminsSeulsAjoutent'] as bool?) ?? true,
      historiqueCacheNouveaux: (g['historiqueCacheNouveaux'] as bool?) ?? false,
      arriveeAConfirmer: (moi?['arriveeAConfirmer'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'groupe': {
          'description': description,
          'proprietaireId': proprietaireId,
          'adminsSeulsEcrivent': adminsSeulsEcrivent,
          'adminsSeulsModifient': adminsSeulsModifient,
          'adminsSeulsAjoutent': adminsSeulsAjoutent,
          'historiqueCacheNouveaux': historiqueCacheNouveaux,
        },
        'moi': {'arriveeAConfirmer': arriveeAConfirmer},
      };

  ReglagesGroupe copyWith({
    String? description,
    bool effacerDescription = false,
    bool? adminsSeulsEcrivent,
    bool? adminsSeulsModifient,
    bool? adminsSeulsAjoutent,
    bool? historiqueCacheNouveaux,
    bool? arriveeAConfirmer,
  }) =>
      ReglagesGroupe(
        description: effacerDescription ? null : (description ?? this.description),
        proprietaireId: proprietaireId,
        adminsSeulsEcrivent: adminsSeulsEcrivent ?? this.adminsSeulsEcrivent,
        adminsSeulsModifient: adminsSeulsModifient ?? this.adminsSeulsModifient,
        adminsSeulsAjoutent: adminsSeulsAjoutent ?? this.adminsSeulsAjoutent,
        historiqueCacheNouveaux: historiqueCacheNouveaux ?? this.historiqueCacheNouveaux,
        arriveeAConfirmer: arriveeAConfirmer ?? this.arriveeAConfirmer,
      );
}

/// L'état de la sourdine d'une conversation, tel que le serveur l'a retenu
/// (01/11/2026) : pour toujours, pour un temps, « mentions seulement ».
class EtatSourdine {
  const EtatSourdine({
    required this.sourdine,
    this.jusqua,
    this.mentionsSeulement = false,
  });

  /// Notifications coupées en ce moment (pour toujours ou pour un temps).
  final bool sourdine;

  /// Fin d'une sourdine pour un temps ; `null` = pour toujours, ou aucune.
  final DateTime? jusqua;

  final bool mentionsSeulement;

  factory EtatSourdine.fromJson(Map<String, dynamic> j) => EtatSourdine(
        sourdine: (j['sourdine'] as bool?) ?? false,
        jusqua: j['sourdineJusqua'] is String
            ? DateTime.tryParse(j['sourdineJusqua'] as String)?.toLocal()
            : null,
        mentionsSeulement: (j['mentionsSeulement'] as bool?) ?? false,
      );
}
