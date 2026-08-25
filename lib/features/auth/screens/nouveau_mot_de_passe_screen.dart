import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../auth_repository.dart';

/// SECOND écran de la reprise par code de récupération : le nouveau mot de
/// passe, saisi deux fois.
///
/// 🔴 IL NE S'OUVRE QU'APRÈS VÉRIFICATION de la paire { code de récupération,
/// Alanya ID } (demande du user, 25/08/2026). Les trois champs vivaient
/// auparavant sur le même écran : on saisissait un mot de passe pour découvrir
/// ensuite que le code était faux, et tout était à refaire.
///
/// ⚠️ CET ÉCRAN N'EST PAS UNE SESSION. La vérification qui l'a ouvert n'a rien
/// autorisé et n'a émis aucun jeton : ce sont le code et l'Alanya ID, portés
/// jusqu'ici, qui autorisent la réinitialisation, et le serveur les revérifie.
/// C'est pourquoi ils sont exigés par le constructeur plutôt que relus d'un
/// état global — un écran qui aurait perdu ces deux valeurs ne peut rien faire,
/// et il vaut mieux que cela ne compile pas.
///
/// 🔴 LA CONFIRMATION N'EST PAS UNE FORMALITÉ ICI. Ailleurs, une faute de
/// frappe se rattrape en redemandant un code par courriel ; sur un compte sans
/// adresse, le seul recours est ce code de récupération, dont les essais sont
/// plafonnés. Un mot de passe mal tapé sans confirmation enfermerait donc
/// quelqu'un dehors avec, au mieux, quelques essais avant le quart d'heure
/// d'attente.
class NouveauMotDePasseScreen extends StatefulWidget {
  const NouveauMotDePasseScreen({
    super.key,
    required this.idRecuperation,
    required this.alanyaId,
  });

  /// Le code de récupération, TEL QUE SAISI à l'écran précédent.
  ///
  /// ⚠️ Non nettoyé, volontairement : c'est le serveur qui relève la casse,
  /// ignore les séparateurs et traduit les I/L/O mal lus. Nettoyer ici ferait
  /// une seconde règle à tenir accordée avec la sienne — et l'écran précédent
  /// a déjà fait accepter cette saisie telle quelle.
  final String idRecuperation;

  /// L'Alanya ID du compte, tel que saisi lui aussi.
  final String alanyaId;

  @override
  State<NouveauMotDePasseScreen> createState() => _NouveauMotDePasseScreenState();
}

class _NouveauMotDePasseScreenState extends State<NouveauMotDePasseScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reinitialiser() async {
    final motDePasse = _passCtrl.text;
    final confirmation = _confirmCtrl.text;

    if (motDePasse.length < 8) {
      showAppSnackBar(tr(context, 'password_min_8'));
      return;
    }
    // Comparaison sur le texte BRUT, sans `trim` : un espace de tête ou de fin
    // fait partie du mot de passe, et le retirer d'un côté seulement laisserait
    // passer deux saisies réellement différentes.
    if (motDePasse != confirmation) {
      showAppSnackBar(tr(context, 'passwords_mismatch'));
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<AuthRepository>().resetPasswordParIdRecuperation(
            idRecuperation: widget.idRecuperation,
            alanyaId: widget.alanyaId,
            newPassword: motDePasse,
          );
      if (!mounted) return;
      showAppSnackBar(tr(context, 'recovery_id_reset_done'));
      // Retour à l'accueil, pas à l'écran précédent : le code de récupération
      // vient de servir, et le remontrer avec ses champs remplis inviterait à
      // le rejouer alors que le mot de passe a changé.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      _onError(e.message);
    } catch (_) {
      _onError(tr(context, 'server_unreachable'));
    }
  }

  void _onError(String msg) {
    if (!mounted) return;
    setState(() => _loading = false);
    showAppSnackBar(msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'recovery_new_password_title')),
      body: MotifBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_reset, size: 64, color: accentOf(context)),
                  const SizedBox(height: 16),
                  Text(
                    tr(context, 'recovery_new_password_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, 'recovery_new_password_body'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedOf(context, Colors.black54)),
                  ),
                  const SizedBox(height: 32),

                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: tr(context, 'recovery_id_new_password'),
                      helperText: tr(context, 'password_min_8'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: _obscureConfirm,
                    // `done` et non `next` : c'est le dernier champ, et le
                    // clavier doit refermer plutôt que chercher un suivant.
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _loading ? null : _reinitialiser(),
                    decoration: InputDecoration(
                      labelText: tr(context, 'recovery_id_new_password_confirm'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _reinitialiser,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(tr(context, 'reset_password_action')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
