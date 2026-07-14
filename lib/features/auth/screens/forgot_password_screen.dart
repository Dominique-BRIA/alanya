import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../auth_repository.dart';

/// Écran de réinitialisation de mot de passe (Mot de passe oublié).
/// Étape 1 : Saisie de l'email → Envoi du code OTP.
/// Étape 2 : Saisie du code + Nouveau mot de passe.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _codeSent = false; // Passe à true après l'envoi du code

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Étape 1 : Demande l'envoi du code OTP.
  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showAppSnackBar("Entre un email valide");
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<AuthRepository>().forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _loading = false;
      });
      showAppSnackBar("Un code a été envoyé à cet email (s'il existe).");
    } on ApiException catch (e) {
      _onError(e.message);
    } catch (_) {
      _onError("Erreur réseau. Vérifie ta connexion.");
    }
  }

  /// Étape 2 : Validation du code + nouveau mot de passe.
  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPass = _passCtrl.text;

    if (code.length != 6) {
      showAppSnackBar("Le code doit comporter 6 chiffres");
      return;
    }
    if (newPass.length < 8) {
      showAppSnackBar("Le mot de passe doit faire au moins 8 caractères");
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<AuthRepository>().resetPassword(
            email: email,
            code: code,
            newPassword: newPass,
          );
      if (!mounted) return;
      showAppSnackBar("Mot de passe réinitialisé avec succès 🎉");
      // Retour à l'écran de connexion
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      _onError(e.message);
    } catch (_) {
      _onError("Erreur réseau. Vérifie ta connexion.");
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
      appBar: backAppBar(context, "Mot de passe oublié"),
      body: MotifBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icône
                  const Icon(Icons.lock_reset, size: 64, color: AppColors.terracotta),
                  const SizedBox(height: 16),

                  Text(
                    _codeSent
                        ? "Vérifie ta boîte mail"
                        : "Réinitialise ton mot de passe",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codeSent
                        ? "Saisis le code à 6 chiffres reçu par email et ton nouveau mot de passe."
                        : "Saisis ton adresse email. Si un compte existe, tu recevras un code de vérification.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 32),

                  // Champ Email (toujours visible)
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_codeSent, // Grisé si le code a été envoyé
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),

                  // Champs Code + Mot de passe (visibles seulement après l'envoi du code)
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: "Code de vérification (6 chiffres)",
                        prefixIcon: Icon(Icons.password),
                        counterText: "",
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Nouveau mot de passe",
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Bouton d'action
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading
                          ? null
                          : _codeSent
                              ? _resetPassword
                              : _sendCode,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(_codeSent ? "Réinitialiser" : "Envoyer le code"),
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
