import 'package:flutter/material.dart';

/// AppBar premium avec bouton retour (utilisé dans les sous-écrans).
///
/// Style : fond transparent, titre en gras, bouton retour dans un cercle discret.
PreferredSizeWidget backAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
  VoidCallback? onBack,
  bool transparent = false,
}) {
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    title: Text(title),
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
