import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_repository.dart';
import 'otp_screen.dart';

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
                  style: const TextStyle(color: Colors.black54),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
