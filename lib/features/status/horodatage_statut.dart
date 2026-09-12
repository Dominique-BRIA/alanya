/// Âge d'un statut, en toutes lettres.
///
/// Deux écrans affichent cet âge — la liste de l'onglet Status et l'en-tête de
/// la visionneuse. Ils doivent dire la même chose au même moment, d'où cette
/// fonction partagée plutôt qu'une copie de chaque côté.
///
/// Un statut vit 24 h : au-delà de « il y a 23 h » il a normalement disparu du
/// fil. La branche en jours reste par sûreté, elle ne coûte rien.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
String horodatageStatut(DateTime creeLe, BuildContext context) {
  final diff = DateTime.now().difference(creeLe);
  if (diff.inMinutes < 1) return tr(context, 'status_now');
  if (diff.inMinutes < 60) {
    return tr(context, 'ago_min', {'n': '${diff.inMinutes}'});
  }
  if (diff.inHours < 24) {
    return tr(context, 'ago_hour', {'n': '${diff.inHours}'});
  }
  return tr(context, 'ago_day', {'n': '${diff.inDays}'});
}
