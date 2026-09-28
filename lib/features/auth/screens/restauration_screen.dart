/// L'ÉCRAN ENTRE LA CONNEXION ET LA SESSION : l'historique chiffré revient.
///
/// 🐛 « QUAND JE ME CONNECTE SUR UN NOUVEAU TÉLÉPHONE, L'ARCHIVE NE SE CHARGE
/// PAS » (user, 28/09/2026). La restauration tournait en fond, invisible, et
/// chaque échec était avalé : un mot de passe changé, une archive protégée par
/// la seule clé de récupération, une coupure réseau — même résultat, rien.
///
/// Demande du user : un écran entre la connexion et la session, qui récupère
/// l'archive, la déchiffre, la range en local, et MONTRE où il en est.
///
/// ⚠️ « CONTINUER EN ARRIÈRE-PLAN » (choix du user) : un long historique ne
/// doit pas bloquer l'entrée. La restauration continue alors en fond — elle
/// ne dépend pas de cet écran — et les conversations se remplissent à mesure
/// (`E2eeSauvegarde.restaurations`).
///
/// ⚠️ LE MOT DE PASSE N'EST ÉCRIT NULLE PART : il traverse cet écran, le temps
/// d'ouvrir la serrure.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/e2ee/e2ee_fournisseur.dart';
import '../../../services/e2ee/e2ee_sauvegarde.dart';
import '../../parametres/screens/sauvegarde_chiffree_screen.dart';
import '../restauration_progression.dart';

class RestaurationScreen extends StatefulWidget {
  const RestaurationScreen({super.key, required this.motDePasse});

  final String motDePasse;

  @override
  State<RestaurationScreen> createState() => _RestaurationScreenState();
}

class _RestaurationScreenState extends State<RestaurationScreen> {
  ProgressionRestauration _progression = const ProgressionRestauration(
    EtapeRestauration.ouverture,
    0,
  );

  /// Nulle tant que la restauration tourne.
  IssueConnexion? _issue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _lancer());
  }

  /// La pile de chiffrement du compte qui vient de se connecter.
  ///
  /// ⚠️ ELLE PEUT MANQUER UN INSTANT : `main.dart` la bâtit quand
  /// `AuthController` change, à la reconstruction suivante. On l'attend un
  /// peu, sans jamais bloquer : sans elle, on entre sans restaurer.
  Future<PileE2ee?> _pile() async {
    for (var i = 0; i < 50; i++) {
      if (!mounted) return null;
      final pile = context.e2ee;
      if (pile != null) return pile;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> _lancer() async {
    setState(() {
      _issue = null;
      _progression = const ProgressionRestauration(
        EtapeRestauration.ouverture,
        0,
      );
    });
    final pile = await _pile();
    if (!mounted) return;
    if (pile == null) {
      _entrer();
      return;
    }
    final r = await pile.sauvegarde.ouvrirEtRestaurer(
      widget.motDePasse,
      pile.coffre,
      suivi: (p) {
        if (mounted) setState(() => _progression = p);
      },
    );
    // L'utilisateur a pu choisir « Continuer en arrière-plan » : l'écran n'est
    // plus là, la restauration, elle, est allée au bout.
    if (!mounted) return;
    if (r.issue == IssueConnexion.restauree ||
        r.issue == IssueConnexion.rienARestaurer) {
      _entrer();
      return;
    }
    setState(() => _issue = r.issue);
  }

  void _entrer() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _parCleDeRecuperation() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SauvegardeChiffreeScreen()));
    _entrer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issue = _issue;
    return PopScope(
      // Le retour système équivaut à « Continuer en arrière-plan » : on ne
      // revient pas à l'écran de connexion, la session est déjà ouverte.
      canPop: false,
      onPopInvokedWithResult: (aPoppe, _) {
        if (!aPoppe) _entrer();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  issue == null
                      ? Icons.lock_outline
                      : Icons.lock_person_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  issue == null
                      ? 'Récupération de vos messages'
                      : issue == IssueConnexion.fermee
                      ? 'Votre sauvegarde reste fermée'
                      : 'La récupération n’a pas abouti',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (issue == null)
                  ..._enCours(theme)
                else
                  ..._probleme(theme, issue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _enCours(ThemeData theme) {
    final texteCompteur = compteur(_progression);
    return [
      Text(
        'Vos conversations chiffrées sont déchiffrées sur cet appareil. '
        'Personne d’autre, pas même Alanya, ne peut les lire.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 32),
      Text(libelleEtape(_progression.etape), style: theme.textTheme.bodyLarge),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: fractionGlobale(_progression),
          minHeight: 8,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 20,
        child: texteCompteur == null
            ? null
            : Text(
                texteCompteur,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall,
              ),
      ),
      const SizedBox(height: 28),
      OutlinedButton(
        onPressed: _entrer,
        child: const Text('Continuer en arrière-plan'),
      ),
      const SizedBox(height: 8),
      Text(
        'La récupération se poursuit pendant que vous utilisez l’application.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _probleme(ThemeData theme, IssueConnexion issue) {
    if (issue == IssueConnexion.fermee) {
      return [
        Text(
          'Votre mot de passe n’ouvre pas votre sauvegarde. Il a peut-être '
          'changé depuis sa création, ou elle n’est protégée que par votre clé '
          'de récupération (les 12 mots).',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _parCleDeRecuperation,
          child: const Text('Utiliser ma clé de récupération'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _entrer,
          child: const Text('Continuer sans l’historique'),
        ),
      ];
    }
    return [
      Text(
        'Le serveur n’a pas pu être joint, ou n’a pas répondu comme prévu. '
        'Votre historique est intact : vous pouvez réessayer maintenant, ou '
        'plus tard depuis Réglages › Sauvegarde chiffrée.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 28),
      FilledButton(onPressed: _lancer, child: const Text('Réessayer')),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: _entrer,
        child: const Text('Continuer sans l’historique'),
      ),
    ];
  }
}
