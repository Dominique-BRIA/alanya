import 'package:flutter/widgets.dart';

/// LA PLACE DE LA BARRE DU BAS FLOTTANTE (21/11/2026).
///
/// L'accueil passe `extendBody: true` : la liste défile sous les marges de la
/// barre, qui flotte par-dessus. Le Scaffold de l'accueil annonce alors la
/// hauteur de la barre dans `MediaQuery.padding.bottom` de ses onglets. Une
/// `ListView` SANS marge propre s'en sert d'elle-même ; mais pas :
///  - une liste qui pose sa propre marge (`padding:`) ;
///  - le bouton flottant d'un onglet qui a son propre Scaffold : Flutter le
///    place au bas de son corps sans compter ce padding — il passait SOUS la
///    barre (Réunions, Statuts) ;
///  - un bouton placé à la main (`Positioned(bottom: …)`, Appels).
/// Ceux-là ajoutent [margeBasseBarre].
///
/// ⚠️ À LIRE AVEC LE CONTEXTE DE L'ÉCRAN, pas celui du bouton : le Scaffold
/// d'un onglet retire ce padding à la zone de son bouton flottant (mesuré : 76
/// dans le corps, 0 autour du bouton). D'où le paramètre [AuDessusDeLaBarre.marge].
///
/// Hors de l'accueil (écran poussé seul), cette valeur est la marge système
/// ordinaire : la règle reste juste.
double margeBasseBarre(BuildContext context) => MediaQuery.paddingOf(context).bottom;

/// Remonte un bouton flottant d'onglet au-dessus de la barre du bas.
/// [marge] : `margeBasseBarre(context)` lu dans le `build` de l'ÉCRAN.
class AuDessusDeLaBarre extends StatelessWidget {
  const AuDessusDeLaBarre({super.key, required this.marge, required this.child});

  final double marge;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: marge),
        child: child,
      );
}
