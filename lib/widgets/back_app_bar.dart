import 'package:flutter/material.dart';

/// AppBar premium avec bouton retour (utilisé dans les sous-écrans).
///
/// Style : fond transparent, titre en gras, bouton retour dans un cercle discret.
/// [titreWidget] remplace le titre texte — un champ de recherche, par exemple.
/// Il est optionnel pour que les dizaines d'écrans existants n'aient rien à
/// changer : l'appel à un seul argument reste exactement le même.
PreferredSizeWidget backAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
  VoidCallback? onBack,
  bool transparent = false,
  Widget? titreWidget,
}) {
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    title: titreWidget ?? Text(title),
    backgroundColor: transparent ? Colors.transparent : null,
    scrolledUnderElevation: transparent ? 0 : null,
    automaticallyImplyLeading: false,
    leading: canPop
        ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            tooltip: "Retour",
            onPressed: onBack ?? () => Navigator.maybePop(context),
          )
        : null,
    actions: actions,
  );
}
