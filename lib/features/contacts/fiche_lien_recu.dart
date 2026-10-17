import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alanya_id_formatter.dart';
import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../core/lien_alanya.dart';
import '../../l10n/app_localizations.dart';
import '../../models/contact.dart';
import '../../models/invitation_qr.dart';
import '../../theme/alanya_theme.dart';
import '../../widgets/avatar_circle.dart';
import '../auth/auth_controller.dart';
import 'contacts_repository.dart';
import 'ouvrir_invitation.dart';
import 'ouvrir_profil_scanne.dart';

/// UN LIEN ALANYA A OUVERT L'APPLICATION : on montre à qui il mène, et
/// l'utilisateur confirme d'un appui.
///
/// 🔒 Décision du user (29/09/2026, « option B ») : un lien reçu d'ailleurs
/// ne doit PAS ajouter un contact tout seul. Posté dans un groupe ou caché
/// derrière un texte, il ferait sinon entrer un inconnu dans le répertoire de
/// chaque personne qui clique. Le scan dans l'application, lui, reste direct
/// (`ouvrirProfilScanne`, `utiliserInvitationEtOuvrir`) : scanner est déjà un
/// geste volontaire.
Future<void> proposerLienRecu(BuildContext context, CibleLien cible) async {
  switch (cible) {
    case CibleProfil(:final publicNumber):
      await _proposerProfil(context, publicNumber);
    case CibleInvitation(:final jeton):
      await _proposerInvitation(context, jeton);
  }
}

Future<void> _proposerProfil(BuildContext context, String publicNumber) async {
  final moi = context.read<AuthController>().user;
  if (moi != null && stripAlanyaId(moi.publicNumber) == publicNumber) {
    showAppSnackBar(tr(context, 'qr_scan_self'));
    return;
  }

  final UserSearchResult user;
  try {
    user = await context.read<ContactsRepository>().searchByNumber(
      publicNumber,
    );
  } on ApiException catch (e) {
    if (context.mounted) {
      showAppSnackBar(
        e.statusCode == 404 ? tr(context, 'dial_no_account') : e.message,
      );
    }
    return;
  } catch (_) {
    if (context.mounted) showAppSnackBar(tr(context, 'dial_lookup_failed'));
    return;
  }
  if (!context.mounted) return;

  final nom = user.pseudo ?? formatAlanyaId(user.publicNumber);
  final confirme = await _montrerFiche(
    context,
    entete: tr(context, 'qr_link_received'),
    nom: nom,
    avatarUrl: user.avatarUrl,
    detail: formatAlanyaId(user.publicNumber),
    dejaContact: user.alreadyContact,
  );
  if (confirme != true || !context.mounted) return;
  await ouvrirProfilScanne(context, user.publicNumber);
}

/// 🔒 L'Alanya ID du créateur n'est pas montré : le serveur ne le rend qu'une
/// fois l'invitation utilisée. Le nom et la photo suffisent à le reconnaître.
Future<void> _proposerInvitation(BuildContext context, String jeton) async {
  final messages = MessagesInvitation.de(context);
  final ApercuInvitation apercu;
  try {
    apercu = await context.read<ContactsRepository>().consulterInvitation(
      jeton,
    );
  } on ApiException catch (e) {
    showAppSnackBar(messages.pour(e));
    return;
  } catch (_) {
    if (context.mounted) showAppSnackBar(tr(context, 'dial_lookup_failed'));
    return;
  }
  if (!context.mounted) return;

  if (apercu.estLaMienne) {
    showAppSnackBar(messages.laMienne);
    return;
  }
  // Déjà acceptée par moi (second clic sur le même lien) : rien à confirmer,
  // on rouvre la conversation.
  if (apercu.dejaUtiliseeParMoi) {
    await utiliserInvitationEtOuvrir(context, jeton);
    return;
  }

  final confirme = await _montrerFiche(
    context,
    entete: tr(context, 'invqr_received'),
    nom: apercu.pseudo ?? 'Alanya',
    avatarUrl: apercu.avatarUrl,
    detail: tr(context, 'invqr_single_use'),
    dejaContact: apercu.dejaContact,
  );
  if (confirme != true || !context.mounted) return;
  await utiliserInvitationEtOuvrir(context, jeton);
}

Future<bool?> _montrerFiche(
  BuildContext context, {
  required String entete,
  required String nom,
  required String? avatarUrl,
  required String detail,
  required bool dejaContact,
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  builder: (_) => _Fiche(
    entete: entete,
    nom: nom,
    avatarUrl: avatarUrl,
    detail: detail,
    dejaContact: dejaContact,
  ),
);

class _Fiche extends StatelessWidget {
  final String entete;
  final String nom;
  final String? avatarUrl;

  /// Sous le nom : l'Alanya ID pour un profil, la mention « usage unique »
  /// pour une invitation (qui ne révèle pas l'ID).
  final String detail;
  final bool dejaContact;

  const _Fiche({
    required this.entete,
    required this.nom,
    required this.avatarUrl,
    required this.detail,
    required this.dejaContact,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entete,
              style: TextStyle(color: mutedOf(context, Colors.black54)),
            ),
            const SizedBox(height: 16),
            AvatarCircle(name: nom, avatarUrl: avatarUrl, radius: 36),
            const SizedBox(height: 12),
            Text(
              nom,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedOf(context, Colors.black54),
                letterSpacing: 1,
              ),
            ),
            if (dejaContact) ...[
              const SizedBox(height: 4),
              Text(
                tr(context, 'add_already_in_book'),
                style: TextStyle(
                  color: mutedOf(context, Colors.black45),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  dejaContact
                      ? tr(context, 'qr_link_chat')
                      : tr(context, 'qr_link_add_and_chat'),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr(context, 'cancel')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
