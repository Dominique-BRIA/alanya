import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../collegues/screens/collegues_tab.dart';
import '../entreprises/screens/entreprises_tab.dart';

/// L'ANNUAIRE D'UN AGENT : ses collègues, et les entreprises de son pays.
///
/// 🔴 POURQUOI DEUX VOLETS PLUTÔT QU'UN SIXIÈME ONGLET (choix du user,
/// 27/08/2026, option A). La barre partage sa largeur en parts égales et écrit
/// ses libellés en `fontSize: 10`. À six onglets, chaque part tombe à environ
/// 60 dp sur un écran de 360 — « Entreprises » compte onze caractères et arrive
/// au bord ; sur 320 dp il est coupé. Le sixième onglet ne rentre pas, et il
/// aurait rétréci les cibles tactiles de TOUT LE MONDE, pas seulement celle du
/// nouvel onglet.
///
/// Les deux listes sont d'ailleurs la même chose — des services et des gens
/// qu'on appelle. Les réunir sous « Annuaire » dit cette parenté au lieu de la
/// cacher.
///
/// ⚠️ CET ÉCRAN N'EXISTE QUE POUR LES AGENTS. Un particulier n'a pas de
/// collègues : il garde l'onglet « Entreprises » tel quel, sans sélecteur — son
/// écran ne change pas d'un pixel. Voir `home_screen.dart`.
///
/// ⚠️ AUCUNE RÈGLE D'ACCÈS ICI. Les deux onglets qu'il empile portent déjà les
/// leurs, et c'est le SERVEUR qui tranche : `/api/collegues` répond 403 à qui
/// n'est pas agent, `/api/entreprises` répond à tout le monde — un annuaire de
/// standards publics n'a aucune raison d'être refusé à un agent.
class AnnuaireTab extends StatefulWidget {
  const AnnuaireTab({super.key});

  @override
  State<AnnuaireTab> createState() => _AnnuaireTabState();
}

class _AnnuaireTabState extends State<AnnuaireTab> {
  /// 0 = Collègues, 1 = Entreprises.
  ///
  /// Collègues d'abord : c'est le quotidien d'un agent. Les entreprises sont
  /// une consultation occasionnelle.
  int _volet = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(tr(context, 'directory_colleagues')),
                icon: const Icon(Icons.groups_outlined, size: 18),
              ),
              ButtonSegment(
                value: 1,
                label: Text(tr(context, 'directory_companies')),
                icon: const Icon(Icons.domain_outlined, size: 18),
              ),
            ],
            selected: {_volet},
            onSelectionChanged: (s) => setState(() => _volet = s.first),
            showSelectedIcon: false,
          ),
        ),
        Expanded(
          /*
           * ⚠️ `IndexedStack` ET NON UN SIMPLE ÉCHANGE DE WIDGET.
           *
           * Les deux volets restent MONTÉS. Revenir sur Collègues après un
           * détour par Entreprises retrouve la liste déjà chargée, la recherche
           * déjà tapée et la position de défilement — au lieu de tout relire au
           * serveur à chaque aller-retour.
           *
           * Le prix est de charger les deux à la première ouverture. Il est
           * modeste : deux listes courtes, et le serveur les rend déjà toutes
           * les deux en une requête chacune.
           */
          child: IndexedStack(
            index: _volet,
            // ⚠️ `expand` ET NON LE DÉFAUT `loose`. Les deux volets contiennent
            // des `Expanded` sous une `Column` : avec des contraintes lâches,
            // leur hauteur dépendrait de leur contenu au lieu de la place
            // disponible, et une liste vide laisserait le sélecteur seul en
            // haut d'un écran blanc.
            sizing: StackFit.expand,
            children: const [ColleguesTab(), EntreprisesTab()],
          ),
        ),
      ],
    );
  }
}
