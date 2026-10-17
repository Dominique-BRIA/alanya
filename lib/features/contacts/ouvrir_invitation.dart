import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../l10n/app_localizations.dart';
import 'contacts_repository.dart';
import 'ouvrir_profil_scanne.dart';

/// UNE INVITATION À USAGE UNIQUE : l'utiliser, puis ouvrir la conversation.
///
/// Le serveur fait tout en un seul appel : il consomme l'invitation, ajoute
/// les deux personnes l'une chez l'autre (décision du user : réciproque pour
/// une invitation), et rend la conversation.
///
/// Appelée directement après un scan dans l'application, ou après la fiche
/// de confirmation pour un lien reçu d'ailleurs (`fiche_lien_recu.dart`).
///
/// Renvoie vrai si la conversation a été ouverte.
Future<bool> utiliserInvitationEtOuvrir(
  BuildContext context,
  String jeton, {
  bool remplacer = false,
}) async {
  final contacts = context.read<ContactsRepository>();
  final nav = Navigator.of(context);
  // Les messages sont lus AVANT l'aller-retour : le contexte peut disparaître
  // pendant, le texte à afficher non.
  final messages = MessagesInvitation.de(context);
  try {
    final r = await contacts.utiliserInvitation(jeton);
    final route = routeConversation(r.convId, r.createur);
    if (remplacer) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
    return true;
  } on ApiException catch (e) {
    showAppSnackBar(messages.pour(e));
  } catch (_) {
    showAppSnackBar(messages.echec);
  }
  return false;
}

/// Les refus du serveur, traduits. Ses messages sont en français seulement ;
/// on choisit donc sur le CODE, jamais sur le texte.
class MessagesInvitation {
  final String utilisee;
  final String expiree;
  final String indisponible;
  final String laMienne;
  final String introuvable;
  final String echec;

  MessagesInvitation._({
    required this.utilisee,
    required this.expiree,
    required this.indisponible,
    required this.laMienne,
    required this.introuvable,
    required this.echec,
  });

  factory MessagesInvitation.de(BuildContext context) => MessagesInvitation._(
    utilisee: tr(context, 'invqr_used'),
    expiree: tr(context, 'invqr_expired_err'),
    indisponible: tr(context, 'invqr_unavailable'),
    laMienne: tr(context, 'invqr_own'),
    introuvable: tr(context, 'invqr_not_found'),
    echec: tr(context, 'chat_open_failed'),
  );

  String pour(ApiException e) {
    switch (e.code) {
      case 'INVITATION_UTILISEE':
        return utilisee;
      case 'INVITATION_EXPIREE':
        return expiree;
      case 'INVITATION_INDISPONIBLE':
        return indisponible;
      case 'SELF':
        return laMienne;
      case 'INVITATION_INCONNUE':
        return introuvable;
    }
    return e.statusCode == 404 ? introuvable : echec;
  }
}
