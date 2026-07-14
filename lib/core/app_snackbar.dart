import 'package:flutter/material.dart';

import 'push_service.dart';

/// Affiche un SnackBar via la racine de navigation (sûr après async / hot restart).
void showAppSnackBar(String message) {
  final ctx = PushService.navigatorKey.currentContext;
  if (ctx == null) return;
  final messenger = ScaffoldMessenger.maybeOf(ctx);
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}
