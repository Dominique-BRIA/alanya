import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alanya_id_formatter.dart';
import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_repository.dart';
import '../chat/screens/chat_screen.dart';
import 'contacts_repository.dart';

/// UN ALANYA ID VENU D'UN QR CODE : ajouter le compte aux contacts, puis
/// ouvrir la conversation avec lui.
///
/// Même enchaînement que « Ajouter et écrire » de `AddContactScreen`, sans le
/// formulaire : c'est l'utilisateur qui a scanné, volontairement, le geste
/// vaut consentement. (Un lien reçu d'ailleurs passera, lui, par une fiche à
/// valider — décision du 29/09/2026.)
///
/// Seul celui qui scanne ajoute l'autre : le compte scanné n'est pas touché.
///
/// [remplacer] : l'écran appelant cède sa place à la conversation, pour que
/// le retour ramène à l'accueil et non au pavé.
///
/// Renvoie vrai si la conversation a été ouverte.
Future<bool> ouvrirProfilScanne(
  BuildContext context,
  String publicNumber, {
  bool remplacer = false,
}) async {
  final moi = context.read<AuthController>().user;
  // Le serveur répond 404 à une recherche de soi-même : sans ce contrôle,
  // scanner son propre QR afficherait « aucun compte », ce qui est faux.
  if (moi != null && stripAlanyaId(moi.publicNumber) == publicNumber) {
    showAppSnackBar(tr(context, 'qr_scan_self'));
    return false;
  }

  final contacts = context.read<ContactsRepository>();
  final chat = context.read<ChatRepository>();
  final nav = Navigator.of(context);
  final messageAbsent = tr(context, 'dial_no_account');
  final messageEchec = tr(context, 'chat_open_failed');

  try {
    final user = await contacts.searchByNumber(publicNumber);
    if (!user.alreadyContact) {
      try {
        await contacts.add(user.publicNumber);
      } on ApiException catch (e) {
        // Ajouté entre la recherche et l'ajout (autre appareil du compte) :
        // le but est atteint, on continue vers la conversation.
        if (e.code != 'ALREADY_CONTACT') rethrow;
      }
    }
    final convId = await chat.createDirect(user.publicNumber);
    final route = MaterialPageRoute(
      builder: (_) => ChatScreen(
        convId: convId,
        title: user.pseudo ?? formatAlanyaId(user.publicNumber),
        avatarUrl: user.avatarUrl,
        otherUserId: user.id,
        otherPublicNumber: user.publicNumber,
        otherStatusMsg: user.statusMsg,
      ),
    );
    // ⚠️ Le `NavigatorState` est pris AVANT les allers-retours réseau : le
    // contexte de l'appelant a pu être démonté entre-temps, le navigateur non.
    if (remplacer) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
    return true;
  } on ApiException catch (e) {
    showAppSnackBar(e.statusCode == 404 ? messageAbsent : e.message);
  } catch (_) {
    showAppSnackBar(messageEchec);
  }
  return false;
}
