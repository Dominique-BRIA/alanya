import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_repository.dart';
import 'otp_screen.dart';
import 'setup_screen.dart';

/// Étape 1 : saisie de l'email pour recevoir le code de confirmation.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailCtrl.text.trim();
    try {
      await context.read<AuthRepository>().register(email);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OtpScreen(email: email)),
      );
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Inscription SANS adresse.
  ///
  /// ⚠️ Le formulaire n'est PAS validé ici : ce chemin ignore le champ, et le
  /// valider refuserait de continuer à cause d'une adresse à moitié tapée que
  /// l'utilisateur vient justement de renoncer à donner.
  ///
  /// Le compte est créé immédiatement — il n'y a pas de code à confirmer — et
  /// l'on enchaîne sur le profil.
  ///
  /// 🔴 L'IDENTIFIANT DE RÉCUPÉRATION EST PRÉSENTÉ À LA FIN, après le profil et
  /// le mot de passe (demande du user, 25/08/2026). Il l'était auparavant juste
  /// ici, avant le mot de passe. Le raisonnement d'alors — « le montrer après
  /// laisserait croire l'inscription finie » — se retournait en fait contre
  /// lui : intercalé au milieu, le code arrivait avant que le compte soit
  /// utilisable, et l'écran était traversé comme une étape de plus. Il est
  /// désormais la dernière chose que voit l'utilisateur, une fois qu'il n'a
  /// plus rien à faire.
  ///
  /// ⚠️ C'est `SetupScreen` qui le montre, et c'est voulu : il est le seul à
  /// savoir quand l'inscription est réellement terminée — le mot de passe posé
  /// et la session obtenue.
  Future<void> _sansEmail() async {
    final confirme = await _confirmerSansEmail();
    if (!confirme || !mounted) return;

    setState(() => _loading = true);
    try {
      final res = await context.read<AuthRepository>().registerSansEmail();
      if (!context.mounted) return;
      final id = res.idRecuperation;
      if (id == null) {
        // Serveur plus ancien, qui ne connaît pas encore l'inscription sans
        // adresse : on le dit plutôt que d'enchaîner sur un écran vide et de
        // laisser un compte sans aucun moyen de reprise.
        showAppSnackBar(tr(context, 'server_unreachable'));
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SetupScreen(
            setupToken: res.setupToken,
            publicNumber: res.publicNumber,
            // Transporté jusqu'au bout du parcours : c'est `SetupScreen` qui
            // le présentera, une fois le compte réellement utilisable.
            idRecuperation: id,
          ),
        ),
      );
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Demande confirmation AVANT de créer le compte.
  ///
  /// Renoncer à l'adresse a une conséquence que l'utilisateur ne peut pas
  /// deviner depuis un simple bouton : il n'aura qu'un code, et le perdre lui
  /// coûtera son compte. Le dire après la création aurait été trop tard.
  Future<bool> _confirmerSansEmail() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr(d, 'no_email_title')),
        content: Text(tr(d, 'no_email_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(tr(d, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(tr(d, 'no_email_confirm')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'register')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  tr(context, 'register_question'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'register_hint'),
                  style: TextStyle(color: mutedOf(context, Colors.black54)),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: tr(context, 'email'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    final value = (v ?? "").trim();
                    if (value.isEmpty) return tr(context, 'email_required');
                    if (!value.contains("@") || !value.contains(".")) {
                      return tr(context, 'email_invalid');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(tr(context, 'receive_code')),
                ),
                const SizedBox(height: 8),
                /*
                 * Second chemin, VOLONTAIREMENT SECONDAIRE.
                 *
                 * L'adresse reste le meilleur choix — elle se retrouve, un code
                 * noté sur un papier se perd — donc elle garde le bouton plein
                 * et ce chemin n'est qu'un lien. Le rendre aussi visible que
                 * l'autre pousserait vers l'option la plus fragile ceux qui
                 * cliquent le premier bouton venu.
                 */
                TextButton(
                  onPressed: _loading ? null : _sansEmail,
                  child: Text(tr(context, 'no_email_link')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
