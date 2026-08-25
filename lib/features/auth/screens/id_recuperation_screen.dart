import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';

/// Présente l'IDENTIFIANT DE RÉCUPÉRATION à qui vient de s'inscrire sans
/// adresse.
///
/// 🔴 CET ÉCRAN N'AFFICHE PAS, IL FAIT NOTER. C'est toute sa raison d'être.
///
/// Sans adresse, cet identifiant est le SEUL moyen de reprendre le compte en
/// cas d'oubli du mot de passe. Le serveur ne le redonnera qu'à quelqu'un de
/// DÉJÀ connecté (`Réglages ▸ Sécurité`) : celui qui le laisse passer ici et
/// oublie son mot de passe avant de s'être reconnecté perd son compte, sans
/// recours. Un écran qu'on traverse d'un geste n'aurait donc pas suffi — d'où
/// la case à cocher qui débloque le bouton.
///
/// ⚠️ Il n'y a PAS de bouton retour, et c'est délibéré : revenir en arrière
/// laisserait un compte créé, sans mot de passe, et un identifiant perdu. Le
/// seul chemin va vers l'avant.
class IdRecuperationScreen extends StatefulWidget {
  const IdRecuperationScreen({
    super.key,
    required this.idRecuperation,
    required this.publicNumber,
    required this.onContinuer,
  });

  final String idRecuperation;
  final String publicNumber;

  /// Appelé quand l'utilisateur a confirmé avoir noté son identifiant.
  final VoidCallback onContinuer;

  @override
  State<IdRecuperationScreen> createState() => _IdRecuperationScreenState();
}

class _IdRecuperationScreenState extends State<IdRecuperationScreen> {
  bool _note = false;

  /// L'identifiant en deux groupes de cinq, pour la recopie à la main.
  ///
  /// ⚠️ PRÉSENTATION SEULEMENT — le serveur attend les 10 caractères sans
  /// séparateur. Il ignore de toute façon les tirets à la saisie, ce qui rend
  /// ce confort sans risque : l'utilisateur peut recopier l'espace avec.
  String get _formate {
    final id = widget.idRecuperation;
    if (id.length != 10) return id;
    return "${id.substring(0, 5)} ${id.substring(5)}";
  }

  Future<void> _copier() async {
    // La valeur BRUTE, sans l'espace d'affichage : ce qui est collé doit
    // pouvoir être renvoyé tel quel.
    await Clipboard.setData(ClipboardData(text: widget.idRecuperation));
    if (!mounted) return;
    showAppSnackBar(tr(context, 'recovery_id_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    return PopScope(
      // Le geste « retour » du système est neutralisé pour la même raison que
      // l'absence de flèche : il n'y a rien derrière cet écran qu'un compte à
      // moitié créé.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Icon(Icons.key_outlined,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'recovery_id_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(context, 'recovery_id_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 24),

                // L'identifiant lui-même, en évidence et en chasse fixe : les
                // caractères ambigus sont déjà exclus de l'alphabet, la chasse
                // fixe évite en plus qu'une police les rapproche visuellement.
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formate,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      fontFamily: "monospace",
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _copier,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: Text(tr(context, 'recovery_id_copy')),
                ),
                const SizedBox(height: 8),

                // Le numéro Alanya est rappelé ICI parce que la reprise en a
                // besoin : l'identifiant sert à réinitialiser le mot de passe,
                // mais c'est avec le numéro qu'on se reconnecte ensuite.
                Text(
                  tr(context, 'recovery_id_your_number')
                      .replaceFirst('{number}', widget.publicNumber),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 20, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(context, 'recovery_id_warning'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                CheckboxListTile(
                  value: _note,
                  onChanged: (v) => setState(() => _note = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(tr(context, 'recovery_id_confirm'),
                      style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  // Désactivé tant que la case n'est pas cochée : c'est le seul
                  // moyen d'obtenir un geste conscient plutôt qu'un appui
                  // réflexe sur « Continuer ».
                  onPressed: _note ? widget.onContinuer : null,
                  child: Text(tr(context, 'continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
