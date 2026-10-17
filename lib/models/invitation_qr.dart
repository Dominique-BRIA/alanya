import 'contact.dart';

/// Une invitation à usage unique qu'on vient de créer (POST /api/invitations).
class InvitationCreee {
  final String jeton;
  final String lien;

  /// Durée de vie annoncée par le serveur (15 minutes).
  ///
  /// ⚠️ Le compte à rebours part de CETTE durée, mesurée à la réception, et
  /// non de `expireLe` : l'horloge d'un téléphone peut avancer ou retarder de
  /// plusieurs minutes, et l'écran afficherait alors une invitation déjà
  /// morte comme valide (ou l'inverse).
  final Duration duree;

  InvitationCreee({
    required this.jeton,
    required this.lien,
    required this.duree,
  });

  factory InvitationCreee.fromJson(Map<String, dynamic> j) => InvitationCreee(
    jeton: j['jeton'] as String,
    lien: j['lien'] as String,
    duree: Duration(seconds: (j['dureeSecondes'] as num?)?.toInt() ?? 900),
  );
}

/// Ce qu'on montre avant d'accepter (GET /api/invitations/<jeton>).
///
/// 🔒 Pas d'Alanya ID : l'invitation ne le révèle qu'une fois utilisée.
class ApercuInvitation {
  final String? pseudo;
  final String? avatarUrl;
  final bool estLaMienne;
  final bool dejaContact;
  final bool dejaUtiliseeParMoi;

  ApercuInvitation({
    required this.pseudo,
    required this.avatarUrl,
    required this.estLaMienne,
    required this.dejaContact,
    required this.dejaUtiliseeParMoi,
  });

  factory ApercuInvitation.fromJson(Map<String, dynamic> j) {
    final c = (j['createur'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ApercuInvitation(
      pseudo: c['pseudo'] as String?,
      avatarUrl: c['avatarUrl'] as String?,
      estLaMienne: j['estLaMienne'] == true,
      dejaContact: j['dejaContact'] == true,
      dejaUtiliseeParMoi: j['dejaUtiliseeParMoi'] == true,
    );
  }
}

/// Invitation utilisée (POST /api/invitations/<jeton>/utiliser) : la
/// conversation, et le créateur avec cette fois son Alanya ID.
class InvitationUtilisee {
  final String convId;
  final UserSearchResult createur;

  InvitationUtilisee({required this.convId, required this.createur});

  factory InvitationUtilisee.fromJson(Map<String, dynamic> j) =>
      InvitationUtilisee(
        convId: j['convId'] as String,
        createur: UserSearchResult.fromJson(
          (j['user'] as Map).cast<String, dynamic>(),
        ),
      );
}
