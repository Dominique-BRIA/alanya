import 'package:flutter/material.dart';

import '../../../models/meeting.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';

/// Une DEMANDE D'INVITATION en attente, telle qu'elle s'affiche.
///
/// 🔴 UN SEUL COMPOSANT POUR LES DEUX ENDROITS QUI LA MONTRENT : la fiche de la
/// réunion, et la liste des membres dans la salle. Les deux doivent proposer
/// exactement les mêmes gestes aux mêmes personnes — une divergence ici ferait
/// qu'on peut accepter depuis un écran et pas depuis l'autre, sans que rien ne
/// l'explique.
///
/// QUI VOIT QUOI, ET C'EST TOUT LE SUJET :
///   - l'ORGANISATEUR tranche : refuser, ou accepter ;
///   - le PROPOSANT ne tranche pas — il retire, tant que rien n'est décidé ;
///   - PERSONNE D'AUTRE ne voit cette tuile, et ce n'est pas ce composant qui
///     s'en charge : le serveur ne rend à chacun que ce qui le regarde
///     (`GET /api/meetings/:id/invite-requests`). Filtrer à l'affichage aurait
///     laissé les demandes des autres traverser le réseau.
///
/// ⚠️ LA PERSONNE PROPOSÉE N'EST AU COURANT DE RIEN. Elle n'apparaît dans
/// aucune de ces listes chez elle, et un refus doit lui rester invisible.
class TuileDemandeInvitation extends StatelessWidget {
  const TuileDemandeInvitation({
    super.key,
    required this.demande,
    required this.jeSuisOrganisateur,
    required this.jeSuisLeProposant,
    required this.actif,
    required this.onAccepter,
    required this.onRefuser,
    required this.onRetirer,
    this.surFondSombre = false,
  });

  final MeetingInviteRequest demande;
  final bool jeSuisOrganisateur;
  final bool jeSuisLeProposant;

  /// Faux pendant qu'une décision part au serveur : les boutons se barrent
  /// plutôt que d'accepter un second appui qui referait le même appel.
  final bool actif;

  final VoidCallback onAccepter;
  final VoidCallback onRefuser;
  final VoidCallback onRetirer;

  /// La salle est en fond noir, la fiche en fond clair. Seules les couleurs de
  /// texte changent — les gestes, eux, sont les mêmes.
  final bool surFondSombre;

  @override
  Widget build(BuildContext context) {
    final couleurTitre = surFondSombre ? Colors.white : null;
    final couleurDetail =
        surFondSombre ? Colors.white54 : mutedOf(context, Colors.black54);

    return ListTile(
      leading: Opacity(
        // Comme les invités attendus juste à côté : ce qui n'est pas encore
        // acquis se lit plus pâle. Ici la personne n'est même pas invitée —
        // elle est proposée.
        opacity: 0.45,
        child: AvatarCircle(
          name: demande.invite.displayName,
          avatarUrl: demande.invite.avatarUrl,
          radius: 18,
          backgroundColor: AlanyaColors.forest,
        ),
      ),
      title: Text(
        demande.invite.displayName,
        style: TextStyle(color: couleurTitre, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        // Le proposant lit « ta demande », les autres lisent qui a proposé :
        // « Proposé par Dominique » n'apprend rien à Dominique.
        jeSuisLeProposant
            ? "Ta demande · en attente"
            : "Proposé par ${demande.demandeur.displayName}",
        style: TextStyle(fontSize: 12, color: couleurDetail),
      ),
      trailing: jeSuisOrganisateur
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "Refuser",
                  icon: Icon(Icons.close, color: dangerOf(context)),
                  onPressed: actif ? onRefuser : null,
                ),
                IconButton(
                  tooltip: "Accepter",
                  icon: Icon(Icons.check, color: positiveOf(context)),
                  onPressed: actif ? onAccepter : null,
                ),
              ],
            )
          : jeSuisLeProposant
              ? TextButton(
                  onPressed: actif ? onRetirer : null,
                  child: Text(
                    "Retirer",
                    style: TextStyle(color: dangerOf(context)),
                  ),
                )
              // Ne devrait pas arriver — le serveur ne rend pas cette demande à
              // un tiers. Rien plutôt qu'un bouton sans effet : si ce cas se
              // produit un jour, il ne donnera aucun pouvoir à personne.
              : null,
    );
  }
}
