import 'package:flutter/material.dart';

/// AppBar avec bouton retour explicite (Linux/desktop + mobile).
PreferredSizeWidget backAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
  VoidCallback? onBack,
}) {
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    title: Text(title),
    automaticallyImplyLeading: false,
    leading: canPop
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: "Retour",
            onPressed: onBack ?? () => Navigator.maybePop(context),
          )
        : null,
    actions: actions,
  );
}
