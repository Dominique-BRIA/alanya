import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../l10n/app_localizations.dart';
import '../../models/groupe_lien.dart';
import '../../theme/alanya_theme.dart';
import '../../widgets/avatar_circle.dart';
import '../chat/chat_repository.dart';
import '../chat/screens/chat_screen.dart';

/// LE LIEN (OU LE QR CODE) D'UN GROUPE A ÉTÉ OUVERT (18/11/2026).
///
/// On montre d'abord le groupe — nom, photo, nombre de membres, privé ou
/// public — et l'utilisateur confirme d'un appui :
///   · groupe PUBLIC : il entre, et le groupe s'ouvre ;
///   · groupe PRIVÉ : sa demande part aux administrateurs ; il sera prévenu
///     de leur réponse.
///
/// 🔒 Jamais d'entrée sans confirmation, même après un scan : un lien posté
/// ailleurs ou caché derrière un texte ne doit pas faire entrer quelqu'un
/// dans un groupe à son insu (même règle que les liens de profil,
/// `fiche_lien_recu.dart`).
///
/// [remplacer] : l'écran appelant (le pavé, après un scan) cède sa place au
/// groupe ouvert.
Future<void> proposerGroupe(
  BuildContext context,
  String code, {
  bool remplacer = false,
}) async {
  final repo = context.read<ChatRepository>();
  final nav = Navigator.of(context);
  final messages = _Messages.de(context);

  final ApercuGroupe apercu;
  try {
    apercu = await repo.apercuLienGroupe(code);
  } on ApiException catch (e) {
    showAppSnackBar(e.statusCode == 404 ? messages.invalide : messages.pour(e));
    return;
  } catch (_) {
    showAppSnackBar(messages.echec);
    return;
  }

  // Déjà membre : rien à confirmer, on ouvre le groupe.
  if (apercu.suisMembre) {
    _ouvrir(nav, apercu, remplacer);
    return;
  }
  if (!context.mounted) return;

  final choix = await showModalBottomSheet<_Choix>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _FicheGroupe(apercu: apercu),
  );
  if (choix == null) return;

  try {
    if (choix == _Choix.retirer) {
      await repo.annulerDemandeGroupe(code);
      showAppSnackBar(messages.retiree);
      return;
    }
    final r = await repo.rejoindreParLien(code);
    if (r.membre) {
      _ouvrir(nav, apercu, remplacer);
    } else {
      showAppSnackBar(messages.envoyee);
    }
  } on ApiException catch (e) {
    showAppSnackBar(messages.pour(e));
  } catch (_) {
    showAppSnackBar(messages.echec);
  }
}

void _ouvrir(NavigatorState nav, ApercuGroupe g, bool remplacer) {
  final route = MaterialPageRoute<void>(
    builder: (_) => ChatScreen(
      convId: g.convId,
      title: g.nom ?? '',
      avatarUrl: g.avatarUrl,
      isGroup: true,
    ),
  );
  if (remplacer) {
    nav.pushReplacement(route);
  } else {
    nav.push(route);
  }
}

enum _Choix { rejoindre, retirer }

/// Les refus du serveur, traduits — choisis sur le CODE, jamais sur le texte
/// (le serveur répond en français seulement). Lus AVANT l'aller-retour : le
/// contexte peut disparaître pendant, le texte à afficher non.
class _Messages {
  _Messages._(this.invalide, this.envoyee, this.retiree, this.horsPerimetre,
      this.sansCles, this.echec);

  final String invalide;
  final String envoyee;
  final String retiree;
  final String horsPerimetre;
  final String sansCles;
  final String echec;

  factory _Messages.de(BuildContext context) => _Messages._(
        trLu(context, 'grp_link_invalid'),
        trLu(context, 'grp_join_requested'),
        trLu(context, 'grp_join_cancelled'),
        trLu(context, 'grp_join_out_of_scope'),
        trLu(context, 'grp_join_no_keys'),
        trLu(context, 'chat_open_failed'),
      );

  String pour(ApiException e) => switch (e.code) {
        'LIEN_INVALIDE' => invalide,
        'HORS_PERIMETRE' => horsPerimetre,
        'CLES_MANQUANTES' => sansCles,
        _ => e.statusCode == 404 ? invalide : echec,
      };
}

class _FicheGroupe extends StatelessWidget {
  const _FicheGroupe({required this.apercu});

  final ApercuGroupe apercu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = mutedOf(context, Colors.black54);
    final nom = apercu.nom ?? tr(context, 'grp_link_received');
    final description = apercu.description?.trim() ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(context, 'grp_link_received'), style: TextStyle(color: muted)),
            const SizedBox(height: 16),
            AvatarCircle(name: nom, avatarUrl: apercu.avatarUrl, radius: 36),
            const SizedBox(height: 12),
            Text(
              nom,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface, fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(apercu.estPublic ? Icons.public : Icons.lock_outline, size: 16, color: muted),
                const SizedBox(width: 4),
                Text(
                  tr(context, apercu.estPublic ? 'grp_type_public' : 'grp_type_private'),
                  style: TextStyle(color: muted),
                ),
                Text('  ·  ', style: TextStyle(color: muted)),
                Text(trN(context, 'grp_members_count', apercu.membres), style: TextStyle(color: muted)),
              ],
            ),
            if (apercu.chiffre) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 15, color: muted),
                  const SizedBox(width: 4),
                  Text(tr(context, 'grp_join_encrypted'), style: TextStyle(color: muted, fontSize: 12.5)),
                ],
              ),
            ],
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              tr(context,
                  apercu.enAttente
                      ? 'grp_join_pending'
                      : apercu.estPublic
                          ? 'grp_type_public_sub'
                          : 'grp_type_private_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (apercu.enAttente)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, _Choix.retirer),
                  child: Text(tr(context, 'grp_join_cancel')),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _Choix.rejoindre),
                  child: Text(tr(context, apercu.estPublic ? 'grp_join' : 'grp_join_request')),
                ),
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(context, apercu.enAttente ? 'close' : 'cancel')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
