import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'app_snackbar.dart';

/// LES PAGES LÉGALES (18/11/2026, exigence du Play Store).
///
/// Publiques sur alanyavox.com, modifiées depuis la console de gestion : le
/// téléphone n'en garde aucune copie, il ouvre toujours la version en vigueur.
class PagesLegales {
  PagesLegales._();

  /// Le web est servi sous /webapp (nginx : la racine est le serveur).
  static const base = 'https://alanyavox.com/webapp';
  static final confidentialite = Uri.parse('$base/confidentialite');
  static final conditions = Uri.parse('$base/conditions');
  static final suppressionCompte = Uri.parse('$base/suppression-compte');

  static Future<void> ouvrir(BuildContext context, Uri adresse) async {
    final echec = tr(context, 'action_failed');
    try {
      if (await launchUrl(adresse, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    showAppSnackBar(echec);
  }
}

/// « En continuant, vous acceptez les Conditions d'utilisation et la Politique
/// de confidentialité », avec les deux liens. Affiché avant de créer un compte.
class MentionAcceptation extends StatefulWidget {
  const MentionAcceptation({super.key});

  @override
  State<MentionAcceptation> createState() => _MentionAcceptationState();
}

class _MentionAcceptationState extends State<MentionAcceptation> {
  late final TapGestureRecognizer _conditions;
  late final TapGestureRecognizer _confidentialite;

  @override
  void initState() {
    super.initState();
    _conditions = TapGestureRecognizer()
      ..onTap = () => PagesLegales.ouvrir(context, PagesLegales.conditions);
    _confidentialite = TapGestureRecognizer()
      ..onTap = () => PagesLegales.ouvrir(context, PagesLegales.confidentialite);
  }

  @override
  void dispose() {
    _conditions.dispose();
    _confidentialite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lien = TextStyle(color: cs.primary, decoration: TextDecoration.underline);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
        children: [
          TextSpan(text: '${tr(context, 'legal_acceptation')} '),
          TextSpan(text: tr(context, 'legal_conditions'), style: lien, recognizer: _conditions),
          TextSpan(text: ' ${tr(context, 'legal_et')} '),
          TextSpan(text: tr(context, 'legal_confidentialite'), style: lien, recognizer: _confidentialite),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
