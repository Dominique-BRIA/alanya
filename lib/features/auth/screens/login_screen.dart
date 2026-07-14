import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_controller.dart';
import '../auth_repository.dart';
import 'forgot_password_screen.dart';
import '../../../theme/app_theme.dart';

/// Formateur qui insère un espace tous les 2 chiffres, uniquement quand le champ
/// ne contient que des chiffres/espaces (numéro Alanya). Si l'utilisateur tape
/// un email, on ne touche à rien.
///
/// - Longueur affichée max : 11 caractères (8 chiffres + 3 espaces = "12 34 56 78")
/// - Gère correctement la position du curseur pendant l'édition (insertions,
///   suppressions, collage).
class _AlanyaNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;

    // Si l'utilisateur tape autre chose que des chiffres/espaces (lettre, @, .),
    // on considère que c'est un email : on laisse passer tel quel.
    if (raw.isNotEmpty && !RegExp(r'^[\d\s]*$').hasMatch(raw)) {
      return newValue;
    }

    // Retire tous les espaces pour obtenir les chiffres purs.
    final digitsOnly = raw.replaceAll(RegExp(r'\s+'), '');
    if (digitsOnly.length > 8) {
      // Limite dure : au-delà de 8 chiffres, on refuse l'ajout.
      return oldValue;
    }

    // Reconstruit avec un espace tous les 2 chiffres.
    final buf = StringBuffer();
    for (int i = 0; i < digitsOnly.length; i++) {
      if (i > 0 && i % 2 == 0) buf.write(' ');
      buf.write(digitsOnly[i]);
    }
    final formatted = buf.toString();

    // Recalcule la position du curseur : on veut qu'il reste à la même position
    // "relative" aux chiffres, pas décalé par les espaces auto-insérés.
    // On compte combien de chiffres il y avait avant l'ancienne position du curseur.
    final oldCursor = newValue.selection.baseOffset.clamp(0, raw.length);
    int digitsBeforeCursor = 0;
    for (int i = 0; i < oldCursor; i++) {
      if (RegExp(r'\d').hasMatch(raw[i])) digitsBeforeCursor++;
    }
    // Retrouve la nouvelle position en avançant du même nombre de chiffres.
    int newCursor = 0;
    int seen = 0;
    while (newCursor < formatted.length && seen < digitsBeforeCursor) {
      if (RegExp(r'\d').hasMatch(formatted[newCursor])) seen++;
      newCursor++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}

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
      // Nettoie les espaces si l'utilisateur a tapé un numéro Alanya formaté.
      // (Le backend attend 6 chiffres bruts, pas "12 34 56".)
      final rawId = _idCtrl.text.trim();
      final identifier = RegExp(r'^[\d\s]+$').hasMatch(rawId)
          ? rawId.replaceAll(RegExp(r'\s+'), '')
          : rawId;

      final session = await context.read<AuthRepository>().login(
            identifier: identifier,
            password: _passwordCtrl.text,
          );
      if (!mounted) return;
      await context.read<AuthController>().completeLogin(session);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
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
                Text(
                  tr(context, 'login_welcome'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _idCtrl,
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: [_AlanyaNumberFormatter()],
                  decoration: InputDecoration(
                    labelText: tr(context, 'email_or_alanya'),
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                  validator: (v) =>
                      (v ?? "").trim().isEmpty ? tr(context, 'email_required') : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: tr(context, 'password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v ?? "").isEmpty ? tr(context, 'password') : null,
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
                    child: const Text(
                      "Mot de passe oublié ?",
                      style: TextStyle(color: AppColors.terracotta),
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
