import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../entreprises_repository.dart';
import '../widgets/carte_centre.dart';

/// Les centres d'UN type — centres d'appel, ou centre vocal.
///
/// 🔴 L'ÉCRAN S'OUVRE MÊME QUAND IL N'Y A AUCUN CENTRE, et c'est la demande du
/// user. La description reste affichée, suivie d'un message disant que ce type
/// n'est pas encore proposé par cette entreprise.
///
/// C'est le contraire de ce que j'avais proposé — griser l'entrée et la rendre
/// inerte. Ce choix-ci est meilleur : la description APPREND quelque chose (ce
/// qu'est un serveur vocal, et qu'on y laisse une plainte en tapant 0), et une
/// entreprise qui n'en a pas encore n'est pas une raison de priver l'utilisateur
/// de cette explication.
///
/// ⚠️ Aucune requête ici : les centres sont déjà chargés par la fiche, qui les
/// rend tous d'un coup. Les redemander par type ferait un aller-retour pour des
/// données qu'on a déjà en main.
class CentresTypeScreen extends StatelessWidget {
  const CentresTypeScreen({
    super.key,
    required this.vocal,
    required this.centres,
  });

  /// Vrai pour les centres vocaux, faux pour les centres d'appel.
  final bool vocal;

  /// Les centres de CE type uniquement — le tri est fait par l'appelant.
  final List<CentreEntreprise> centres;

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);

    // Le titre suit le nombre : « Centre d'appel » au singulier n'a pas de sens
    // devant deux cartes, et le pluriel devant une seule non plus.
    final titre = tr(
      context,
      vocal
          ? (centres.length > 1 ? 'company_vocal_centers' : 'company_vocal_center')
          : (centres.length > 1 ? 'company_call_centers' : 'company_call_center'),
    );

    return Scaffold(
      appBar: backAppBar(context, titre),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            /*
             * L'EXPLICATION EN TÊTE, toujours — c'est elle qui dit à l'appelant
             * ce qui va décrocher et ce qu'il devra faire ensuite. Sans elle, le
             * choix entre deux listes de numéros ne veut rien dire pour
             * quelqu'un qui ne connaît pas la différence.
             */
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accentOf(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    vocal ? Icons.graphic_eq : Icons.headset_mic_outlined,
                    color: accentOf(context),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr(context,
                          vocal ? 'company_vocal_center_desc' : 'company_call_center_desc'),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            if (centres.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                child: Text(
                  tr(context, 'company_type_unavailable'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              )
            else
              for (final c in centres) CarteCentre(centre: c),
          ],
        ),
      ),
    );
  }
}
