import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alanya_id_formatter.dart';
import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../core/lien_alanya.dart';
import '../../l10n/app_localizations.dart';
import '../../models/contact.dart';
import '../../theme/alanya_theme.dart';
import '../../widgets/avatar_circle.dart';
import '../auth/auth_controller.dart';
import 'contacts_repository.dart';
import 'ouvrir_profil_scanne.dart';

/// UN LIEN ALANYA A OUVERT L'APPLICATION : on montre à qui il mène, et
/// l'utilisateur confirme d'un appui.
///
/// 🔒 Décision du user (29/09/2026, « option B ») : un lien reçu d'ailleurs
/// ne doit PAS ajouter un contact tout seul. Posté dans un groupe ou caché
/// derrière un texte, il ferait sinon entrer un inconnu dans le répertoire de
/// chaque personne qui clique. Le scan dans l'application, lui, reste direct
/// (`ouvrirProfilScanne`) : scanner est déjà un geste volontaire.
Future<void> proposerLienRecu(BuildContext context, CibleLien cible) async {
  switch (cible) {
    case CibleProfil(:final publicNumber):
      await _proposerProfil(context, publicNumber);
    case CibleInvitation():
      // Les invitations à usage unique arrivent aux lots 4-5.
      showAppSnackBar(tr(context, 'qr_scan_not_alanya'));
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

  final confirme = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (c) => _Fiche(user: user),
  );
  if (confirme != true || !context.mounted) return;
  await ouvrirProfilScanne(context, user.publicNumber);
}

class _Fiche extends StatelessWidget {
  final UserSearchResult user;
  const _Fiche({required this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nom = user.pseudo ?? formatAlanyaId(user.publicNumber);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(context, 'qr_link_received'),
              style: TextStyle(color: mutedOf(context, Colors.black54)),
            ),
            const SizedBox(height: 16),
            AvatarCircle(name: nom, avatarUrl: user.avatarUrl, radius: 36),
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
              formatAlanyaId(user.publicNumber),
              style: TextStyle(
                color: mutedOf(context, Colors.black54),
                letterSpacing: 1,
              ),
            ),
            if (user.alreadyContact) ...[
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
                  user.alreadyContact
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
