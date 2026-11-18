/// LE LIEN D'UN GROUPE ET SA LISTE D'ATTENTE (18/11/2026).
///
/// Demande du user : chaque groupe a un lien et un QR code. Groupe PUBLIC :
/// l'ouvrir fait entrer aussitôt. Groupe PRIVÉ : la personne passe dans une
/// liste d'attente, et les admins acceptent ou refusent.
///
/// Ce fichier n'importe rien de Flutter, pour rester testable seul.
library;

/// Le lien tel que le rend `GET /api/conversations/:id/lien`.
class LienGroupe {
  const LienGroupe({required this.code, required this.lien, required this.acces});

  final String code;
  final String lien;
  final String acces;

  factory LienGroupe.fromJson(Map<String, dynamic> j) => LienGroupe(
        code: j['code'] as String,
        lien: j['lien'] as String,
        acces: (j['acces'] as String?) == 'public' ? 'public' : 'prive',
      );
}

/// Ce que montre un lien de groupe AVANT de confirmer
/// (`GET /api/groupes/lien/:code`). Pas la liste des membres : on n'en est
/// pas encore.
class ApercuGroupe {
  const ApercuGroupe({
    required this.convId,
    required this.nom,
    required this.description,
    required this.avatarUrl,
    required this.membres,
    required this.acces,
    required this.chiffre,
    required this.etat,
  });

  final String convId;
  final String? nom;
  final String? description;
  final String? avatarUrl;
  final int membres;
  final String acces;
  final bool chiffre;

  /// « membre », « attente » ou « aucun ».
  final String etat;

  bool get estPublic => acces == 'public';
  bool get suisMembre => etat == 'membre';
  bool get enAttente => etat == 'attente';

  factory ApercuGroupe.fromJson(Map<String, dynamic> j) => ApercuGroupe(
        convId: j['convId'] as String,
        nom: j['nom'] as String?,
        description: j['description'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        membres: (j['membres'] as num?)?.toInt() ?? 0,
        acces: (j['acces'] as String?) == 'public' ? 'public' : 'prive',
        chiffre: (j['chiffre'] as bool?) ?? false,
        etat: switch (j['etat']) {
          'membre' => 'membre',
          'attente' => 'attente',
          _ => 'aucun',
        },
      );
}

/// La réponse à « Rejoindre » : membre (public), ou en attente (privé).
class ResultatRejoindre {
  const ResultatRejoindre({required this.convId, required this.membre});

  final String convId;

  /// Vrai : on est dans le groupe. Faux : la demande attend les admins.
  final bool membre;

  factory ResultatRejoindre.fromJson(Map<String, dynamic> j) => ResultatRejoindre(
        convId: j['convId'] as String,
        membre: j['etat'] == 'membre',
      );
}

/// Une demande en attente, vue par un admin.
class DemandeAdhesion {
  const DemandeAdhesion({
    required this.id,
    required this.userId,
    required this.pseudo,
    required this.publicNumber,
    required this.avatarUrl,
    required this.creeLe,
  });

  final String id;
  final String userId;
  final String pseudo;
  final String publicNumber;
  final String? avatarUrl;
  final DateTime? creeLe;

  factory DemandeAdhesion.fromJson(Map<String, dynamic> j) => DemandeAdhesion(
        id: j['id'] as String,
        userId: j['userId'] as String,
        pseudo: (j['pseudo'] as String?) ?? '',
        publicNumber: (j['publicNumber'] as String?) ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        creeLe: j['creeLe'] is String ? DateTime.tryParse(j['creeLe'] as String)?.toLocal() : null,
      );
}
