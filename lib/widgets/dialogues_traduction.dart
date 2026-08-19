import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Les deux boîtes de dialogue de la traduction sur l'appareil.
///
/// Elles vivent ici et non dans un écran parce que **deux** appelants s'en
/// servent — le fil de discussion, où l'on découvre qu'une langue manque, et
/// l'écran Réglages ▸ Traduction, où on les installe à l'avance. Les dupliquer
/// aurait fait diverger le texte qui explique où part le message, c'est-à-dire
/// la seule phrase qui compte ici.

/// Demande l'autorisation d'installer les modèles d'un couple.
///
/// [libelleLangues] est déjà mis en forme par l'appelant (« Français + العربية »),
/// parce que lui seul sait s'il s'agit d'une langue ou de deux.
Future<bool> confirmerInstallationLangues(
  BuildContext context,
  String libelleLangues,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'translation_download_title')),
      content: Text(
        tr(ctx, 'translation_download_body', {'langues': libelleLangues}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr(ctx, 'cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr(ctx, 'download')),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Proposée APRÈS un échec d'installation.
///
/// C'est la réparation du défaut le plus gênant du premier lot : le
/// téléchargement n'accepte que le Wi-Fi par défaut, et son échec ne disait pas
/// pourquoi — en données mobiles, l'utilisateur lisait « Installation
/// impossible » sans le moindre recours. Impossible de distinguer « pas de
/// Wi-Fi » d'« aucun réseau » (ML Kit ne rend qu'un booléen), donc le texte ne
/// l'affirme pas : il expose la restriction et laisse décider.
Future<bool> proposerDonneesMobiles(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'translation_mobile_data_title')),
      content: Text(tr(ctx, 'translation_mobile_data_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr(ctx, 'cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr(ctx, 'retry')),
        ),
      ],
    ),
  );
  return ok == true;
}
