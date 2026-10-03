import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';

/// Le dernier écran de l'inscription : l'Alanya ID, et le code de récupération
/// quand il y en a un.
///
/// 🔴 L'ALANYA ID EST MONTRÉ ICI ET NULLE PART AILLEURS DANS LE PARCOURS
/// (demande du user, 26/08/2026). Il trônait auparavant en tête de l'écran de
/// profil, avant même que le compte existe vraiment : on le lisait alors qu'on
/// avait encore trois champs à remplir, donc on ne le lisait pas. Le montrer à
/// la fin le met au seul moment où il compte — celui où il n'y a plus rien à
/// faire que le noter.
///
/// 🔴 CET ÉCRAN N'AFFICHE PAS, IL FAIT NOTER. Deux informations, deux rôles :
///   - l'ALANYA ID est l'identifiant de connexion, et ce que les contacts
///     composent pour appeler. Il se retrouve dans les réglages, et une adresse
///     électronique permet aussi de se reconnecter ;
///   - le CODE DE RÉCUPÉRATION, lui, n'existe que pour les comptes SANS
///     adresse, et c'est le seul moyen de reprendre le compte en cas d'oubli du
///     mot de passe. Le serveur ne le redonne qu'à quelqu'un de DÉJÀ connecté :
///     qui le laisse passer ici et oublie son mot de passe avant de s'être
///     reconnecté perd son compte, sans recours.
///
/// ⚠️ LA CASE À COCHER NE S'IMPOSE QUE POUR LE CODE, et c'est la conséquence
/// directe de ce qui précède. Barrer le bouton pour l'Alanya ID seul ferait
/// payer à tout le monde une précaution qui ne protège rien : il est
/// récupérable. La case reste là où l'oubli est irréversible.
///
/// ⚠️ Il n'y a PAS de bouton retour, et c'est délibéré : revenir en arrière
/// laisserait un compte créé et un code perdu. Le seul chemin va vers l'avant.
class FinInscriptionScreen extends StatefulWidget {
  const FinInscriptionScreen({
    super.key,
    required this.publicNumber,
    required this.onContinuer,
    this.idRecuperation,
  });

  final String publicNumber;

  /// Le code de récupération d'une inscription SANS adresse. `null` quand le
  /// compte porte une adresse électronique — il n'en existe alors aucun.
  final String? idRecuperation;

  final VoidCallback onContinuer;

  @override
  State<FinInscriptionScreen> createState() => _FinInscriptionScreenState();
}

class _FinInscriptionScreenState extends State<FinInscriptionScreen> {
  bool _note = false;

  /// Le code en deux groupes de cinq, pour la recopie à la main.
  ///
  /// ⚠️ PRÉSENTATION SEULEMENT — le serveur attend les 10 caractères sans
  /// séparateur. Il ignore de toute façon les espaces à la saisie, ce qui rend
  /// ce confort sans risque.
  String _codeFormate(String id) =>
      id.length != 10 ? id : "${id.substring(0, 5)} ${id.substring(5)}";

  Future<void> _copier(String valeur, String message) async {
    // La valeur BRUTE, sans les espaces d'affichage : ce qui est collé doit
    // pouvoir être renvoyé tel quel.
    await Clipboard.setData(ClipboardData(text: valeur));
    if (!mounted) return;
    showAppSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    final accent = accentOf(context);
    final code = widget.idRecuperation;

    return PopScope(
      // Le geste « retour » du système est neutralisé pour la même raison que
      // l'absence de flèche : il n'y a rien derrière cet écran.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Icon(Icons.check_circle_outline, size: 48, color: accent),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'signup_done_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // ── L'ALANYA ID ────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        tr(context, 'alanya_number'),
                        style: TextStyle(
                            color: alanyaIdOf(context, AlanyaColors.chocolate),
                            fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatAlanyaId(widget.publicNumber),
                        style: TextStyle(
                          // Le formatage apporte déjà des espaces : un
                          // letterSpacing élevé par-dessus disloquerait les
                          // groupes au lieu de les séparer.
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(context, 'signup_done_number_help'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
                      ),
                      TextButton.icon(
                        onPressed: () => _copier(widget.publicNumber,
                            tr(context, 'alanya_number_copied')),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: Text(tr(context, 'recovery_id_copy')),
                      ),
                    ],
                  ),
                ),

                // ── LE CODE DE RÉCUPÉRATION, s'il y en a un ────────────────
                if (code != null) ...[
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Icon(Icons.key_outlined, size: 20, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(context, 'recovery_id_title'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, 'recovery_id_body'),
                    style: TextStyle(color: muted, fontSize: 13.5, height: 1.45),
                  ),
                  const SizedBox(height: 14),

                  // Le code en chasse fixe : les caractères ambigus sont déjà
                  // exclus de l'alphabet, la chasse fixe évite en plus qu'une
                  // police les rapproche visuellement.
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _codeFormate(code),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        fontFamily: "monospace",
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _copier(code, tr(context, 'recovery_id_copied')),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(tr(context, 'recovery_id_copy')),
                  ),
                  CheckboxListTile(
                    value: _note,
                    onChanged: (v) => setState(() => _note = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(tr(context, 'recovery_id_confirm'),
                        style: const TextStyle(fontSize: 14)),
                  ),
                ],

                const SizedBox(height: 16),
                ElevatedButton(
                  // Barré tant que la case n'est pas cochée — mais seulement
                  // quand il y a un code : c'est le seul moyen d'obtenir un
                  // geste conscient plutôt qu'un appui réflexe sur
                  // « Continuer ». Sans code, rien d'irréversible ne se joue.
                  onPressed:
                      (code == null || _note) ? widget.onContinuer : null,
                  child: Text(tr(context, 'continue')),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
