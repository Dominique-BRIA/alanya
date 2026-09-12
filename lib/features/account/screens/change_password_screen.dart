import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../account_repository.dart';
import '../../../l10n/app_localizations.dart';

/// Écran de changement de mot de passe (utilisateur connecté).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _new.text;
    final confirm = _confirm.text;

    if (current.isEmpty) {
      setState(() => _error = "Saisis ton mot de passe actuel.");
      return;
    }
    if (next.length < 8) {
      setState(() => _error = tr(context, 'password_too_short'));
      return;
    }
    if (next != confirm) {
      setState(() => _error = "Les deux nouveaux mots de passe ne correspondent pas.");
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AccountRepository>().changePassword(current, next);
      if (!mounted) return;
      showAppSnackBar(tr(context, 'password_changed'));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'error_occurred_retry'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Changer le mot de passe"),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field(
            controller: _current,
            label: tr(context, 'current_password'),
            obscure: _obscureCurrent,
            onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
          ),
          const SizedBox(height: 16),
          _field(
            controller: _new,
            label: tr(context, 'recovery_id_new_password'),
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          const SizedBox(height: 16),
          _field(
            controller: _confirm,
            label: tr(context, 'confirm_new_password'),
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'password_min_8'),
            style: TextStyle(
                fontSize: 12,
                color: themed(context,
                    light: AlanyaColors.grey500, dark: AlanyaColors.craie2)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: TextStyle(
                    color: themed(context,
                        light: AlanyaColors.error,
                        dark: AlanyaColors.erreurNuit),
                    fontSize: 13)),
          ],
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                : Text(tr(context, 'save')),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
