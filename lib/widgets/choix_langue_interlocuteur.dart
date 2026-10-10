import 'package:flutter/material.dart';
// `bcpCode` est porté par une extension de ce paquet : sans l'import, la
// liste des langues ne compile pas.
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:provider/provider.dart';

import '../core/app_snackbar.dart';
import '../core/locale_controller.dart';
import '../core/memoire_langues.dart';
import '../core/traduction_appareil.dart';
import '../l10n/app_localizations.dart';
import '../theme/alanya_theme.dart';
import 'dialogues_traduction.dart';

/// Fixer la langue d'un interlocuteur : la liste des langues, l'enregistrement
/// et l'installation du paquet.
///
/// ⚠️ UN SEUL EXEMPLAIRE, DÉLIBÉRÉMENT. Ce geste s'atteint depuis DEUX endroits
/// — la fiche du contact (« Langue de {nom} ») et le bandeau de la conversation
/// quand la traduction automatique ne peut pas travailler. Deux copies de la
/// liste, ce serait deux façons de retenir « auto », et un jour deux réponses
/// différentes à la même question.

/// Ce que rend [choisirLangueInterlocuteur] : `null` si l'utilisateur a refermé
/// la feuille, sinon la langue retenue — `langue == null` valant « auto ».
typedef ChoixLangue = ({String? langue});

/// Ouvre la liste des langues pour [userId] et RETIENT le choix.
///
/// La langue cochée est relue en base à l'ouverture : c'est elle qui fait foi,
/// pas un état d'écran qui aurait pu vieillir.
///
/// N'installe rien : voir [installerCoupleSiNecessaire], que l'appelant lance
/// ensuite. Les deux sont séparés pour que l'écran appelant puisse se rafraîchir
/// AVANT le téléchargement, qui demande confirmation et peut durer.
Future<ChoixLangue?> choisirLangueInterlocuteur(
  BuildContext context, {
  required String userId,
  required String nom,
}) async {
  final actuelle = await MemoireLangues.langueFixee(userId);
  if (!context.mounted) return null;

  final choix = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final langues = languesTraduisibles();
      return SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          // +1 : la première ligne est « Auto », qui n'est pas une langue.
          itemCount: langues.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return ListTile(
                leading: Icon(
                  Icons.auto_awesome_outlined,
                  color: accentOf(context),
                ),
                title: Text(tr(context, 'lang_auto')),
                trailing: actuelle == null
                    ? Icon(Icons.check, color: accentOf(context))
                    : null,
                onTap: () => Navigator.pop(ctx, ""),
              );
            }
            final code = langues[i - 1].bcpCode;
            return ListTile(
              title: Text(nomAutonyme(code)),
              trailing: actuelle == code
                  ? Icon(Icons.check, color: accentOf(context))
                  : null,
              onTap: () => Navigator.pop(ctx, code),
            );
          },
        ),
      );
    },
  );
  if (choix == null || !context.mounted) return null;

  // La chaîne vide porte « auto » : `null` voudrait dire « annulé », et les
  // deux ne se distingueraient plus au retour de la feuille.
  final langue = choix.isEmpty ? null : choix;
  await MemoireLangues.fixe(userId, langue);
  if (!context.mounted) return (langue: langue);
  showAppSnackBar(
    langue == null
        ? tr(context, 'lang_auto_detected')
        : tr(context, 'ci_read_as', {
            'nom': nom,
            'langue': nomAutonyme(langue),
          }),
  );
  return (langue: langue);
}

/// Installe le couple de langues DANS LA FOULÉE, une seule fois.
///
/// 🔴 DEMANDE DU USER (31/08/2026), et c'est le bon moment : fixer la langue
/// de quelqu'un, c'est annoncer qu'on va lire ses messages traduits. Attendre
/// le premier message pour découvrir qu'il manque un modèle repousse le
/// téléchargement au pire instant — celui où l'on veut lire, souvent sans
/// Wi-Fi.
///
/// ⚠️ « UNE FOIS » AU SENS STRICT : si le couple est déjà prêt, rien ne se
/// passe et rien ne s'affiche. La question n'est reposée que si l'état change
/// — modèle évincé par le système, ou langue de lecture changée.
///
/// ⚠️ LE TÉLÉCHARGEMENT RESTE UN GESTE : la confirmation habituelle annonce
/// le poids, et le repli données mobiles n'est proposé que si le Wi-Fi était
/// bien la contrainte. On ne tire pas des dizaines de mégaoctets parce que
/// quelqu'un a touché un menu.
Future<void> installerCoupleSiNecessaire(
  BuildContext context,
  String source,
) async {
  final cible = context.read<LocaleController>().languageCode;
  final etat = await etatCouple(source, cible);
  if (!context.mounted) return;
  // `pret` : déjà là. `indisponible` : même langue que la mienne, ou langue
  // non traduisible — dans les deux cas il n'y a rien à télécharger, et
  // proposer une installation impossible serait trompeur.
  if (etat != EtatCouple.aTelecharger) return;

  final manquantes = await nomsLanguesManquantes(source, cible);
  if (!context.mounted) return;
  final libelle = manquantes.isEmpty
      ? nomAutonyme(source)
      : manquantes.join(" + ");
  if (!await confirmerInstallationLangues(context, libelle)) return;
  if (!context.mounted) return;

  var installe = await telechargerCouple(source, cible);
  if (!installe &&
      wifiExige &&
      context.mounted &&
      await proposerDonneesMobiles(context)) {
    installe = await telechargerCouple(source, cible, wifiSeulement: false);
  }
  if (!context.mounted) return;
  showAppSnackBar(
    installe
        ? tr(context, 'lang_installed', {'langue': nomAutonyme(source)})
        : tr(context, 'trans_install_failed'),
  );
}
