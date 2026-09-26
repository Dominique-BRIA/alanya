import 'dart:async';
import '../../../services/e2ee/e2ee_fournisseur.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_controller.dart';
import '../auth_repository.dart';
import 'forgot_password_screen.dart';
import '../../../theme/alanya_theme.dart';
import '../../../core/alanya_id_formatter.dart';
import '../../../core/nature_echec.dart';

/// Connexion par email OU numéro public (6 ou 8 chiffres) + mot de passe.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // Nettoie les espaces si l'utilisateur a tapé un Alanya ID formaté.
      // (Le backend attend le numéro brut, sans espaces.)
      final rawId = _idCtrl.text.trim();
      final identifier =
          RegExp(r'^[\d\s]+$').hasMatch(rawId) ? stripAlanyaId(rawId) : rawId;

      final session = await context.read<AuthRepository>().login(
            identifier: identifier,
            password: _passwordCtrl.text,
          );
      if (!mounted) return;
      await context.read<AuthController>().completeLogin(session);

      /*
       * 🔴 LE MOT DE PASSE EST DÉJÀ LÀ — l utilisateur vient de le taper. C est
       * le seul moment du cycle de vie où ce secret existe sans qu on ait à le
       * redemander, et c est ce qui permet d ouvrir la sauvegarde sans rien
       * demander de plus.
       *
       * ⚠️ IL N EST GARDÉ NULLE PART : il traverse cet appel et en sort.
       *
       * ⚠️ SANS ATTENDRE, ET SANS JAMAIS BLOQUER : empêcher quelqu un d entrer
       * parce qu une sauvegarde a échoué serait bien pire que l absence
       * d historique.
       */
      unawaited(
        context.e2ee?.sauvegarde
                .aLaConnexion(_passwordCtrl.text, context.e2ee!.coffre) ??
            Future<({int illisibles, int restaures})>.value(
                (restaures: 0, illisibles: 0)),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (e) {
      /*
       * 🔴 CLASSÉ, et non « serveur injoignable » par défaut. Ce `catch` avalait
       * un certificat refusé, une réponse 200 que `AuthUser.fromJson` ne sait pas
       * lire, une écriture de coffre qui échoue — et renvoyait tout le monde au
       * même « Impossible de contacter le serveur », pendant que le serveur, lui,
       * répondait très bien.
       *
       * ⚠️ LE JOURNAL PORTE LE DÉTAIL, le texte montré reste court. Sans la
       * ligne de `traceEchecConnexion`, un défaut de chaîne de certificats se
       * diagnostiquerait par ouï-dire : c'est elle qui dit `CERTIFICATE_VERIFY_FAILED`.
       *
       * Les quatre autres écrans du parcours font exactement la même chose, et
       * pointent ici plutôt que de recopier ce commentaire.
       */
      traceEchecConnexion(e);
      showAppSnackBar(tr(context, cleEchecDe(e)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.waving_hand, size: 24, color: AlanyaColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(context, 'login_welcome'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                // Pourquoi la session s'est fermée, quand ce n'est pas
                // l'utilisateur qui l'a voulu. Sans ce bandeau, quelqu'un
                // éjecté parce que son compte vient d'être ouvert ailleurs
                // retrouve l'écran de connexion sans la moindre explication —
                // et le prend pour une panne.
                if (context.watch<AuthController>().messageDeconnexion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AlanyaColors.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 20, color: AlanyaColors.gold),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context
                                  .watch<AuthController>()
                                  .messageDeconnexion!,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _idCtrl,
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: const [
                    AlanyaIdInputFormatter(maxDigits: 10, allowNonDigits: true)
                  ],
                  decoration: InputDecoration(
                    labelText: tr(context, 'email_or_alanya'),
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                  validator: (v) => (v ?? "").trim().isEmpty
                      ? tr(context, 'email_required')
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: tr(context, 'password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v ?? "").isEmpty ? tr(context, 'password') : null,
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
                      : Text(tr(context, 'sign_in')),
                ),
                const SizedBox(height: 16),
                // Lien mot de passe oublié
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      );
                    },
                    child: Text(
                      tr(context, 'forgot_password'),
                      style: TextStyle(color: accentOf(context)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
