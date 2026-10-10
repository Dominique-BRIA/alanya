/// OUVRIR L'ÉCRAN DE VÉRIFICATION DU CODE DE SÉCURITÉ D'UN CORRESPONDANT.
///
/// Sortie de `contact_info_screen.dart` le 02/10/2026 pour servir AUSSI au
/// bandeau « code de sécurité modifié » de la conversation : son bouton
/// « Vérifier le code » ne faisait qu'afficher un conseil (« ouvrez les infos
/// du contact, puis Chiffrement… ») au lieu d'ouvrir l'écran lui-même.
library;

import 'package:flutter/material.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:provider/provider.dart';

import '../../core/app_snackbar.dart';
import '../../core/erreur_lisible.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../../widgets/e2ee/e2ee_widgets.dart';
import '../auth/auth_controller.dart';

/// Calcule les codes de sécurité de [pairId] (un par appareil) et ouvre
/// l'écran de vérification. Ne lève jamais : une panne s'affiche.
Future<void> ouvrirVerificationCle(
  BuildContext context, {
  required String pairId,
  required String nomPair,
}) async {
  final pile = context.e2ee;
  final monId = context.read<AuthController>().user?.id;
  if (pile == null || monId == null) return;
  final navigateur = Navigator.of(context);
  try {
    /*
     * 🔴 ON OUVRE LA SESSION NOUS-MÊMES PLUTÔT QUE D'EXIGER UN ÉCHANGE.
     *
     * 🐛 Le code réclamait la clé du correspondant dans le coffre local, et
     * disait « échangez d'abord un message chiffré » quand elle manquait.
     * Or vérifier AVANT d'écrire est précisément à quoi sert un code de
     * sécurité : exiger l'échange d'abord retourne l'outil contre son usage.
     *
     * `ouvrirSessions` va chercher le paquet de pré-clés, vérifie sa
     * signature et range l'identité — exactement ce que ferait le premier
     * envoi, sans envoyer.
     */
    final appareils = await pile.service.ouvrirSessions(pairId);
    if (appareils.isEmpty) {
      throw StateError("Ce contact n’a aucun appareil chiffré.");
    }

    /*
     * 🔴 UN CODE PAR APPAREIL, comme le web. Le mobile n'en montrait qu'UN,
     * celui du premier appareil de la liste.
     *
     * ⚠️ LE CODE COMPARE DEUX CLÉS D'IDENTITÉ, et le correspondant en a une
     * par appareil. N'en afficher qu'une laissait les autres invisibles — et
     * c'est précisément un appareil qu'on n'aurait pas remarqué qui serait
     * celui d'un intrus.
     */
    final codes = <CodeAppareil>[];
    for (final appareil in appareils) {
      codes.add(CodeAppareil(
        deviceId: appareil,
        code: await pile.service.codeSecurite(
          monId: monId,
          pairId: pairId,
          adressePair: SignalProtocolAddress(pairId, appareil),
        ),
      ));
    }

    await navigateur.push(MaterialPageRoute(
      builder: (_) => EcranVerification(
        codes: codes,
        nomPair: nomPair,
        verifie: false,
        onBasculer: () => navigateur.pop(),
      ),
    ));
  } catch (e) {
    if (!context.mounted) return;
    // ⚠️ On nomme la panne au lieu d'affirmer une cause : trois fois cette
    // semaine, la cause devinée était la mauvaise.
    showAppSnackBar(messageDErreur(context, e));
  }
}
