import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../auth/auth_controller.dart';
import '../account_repository.dart';
import '../../../l10n/app_localizations.dart';

/// Suppression définitive du compte : avertissement + vérification du mot de
/// passe. Action irréversible → double garde (mot de passe + confirmation).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDelete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = "Saisis ton mot de passe pour confirmer.");
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'delete_permanently_q')),
        content: Text(
            tr(context, 'account_delete_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, 'cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'delete'),
                style: const TextStyle(color: AlanyaColors.error)),
          ),
        ],
      ),
    );
    if (sure != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AccountRepository>().deleteAccount(_password.text);
      if (!mounted) return;
      // Compte supprimé : déconnexion locale (best-effort) puis retour à l'accueil.
      try {
        await context.read<AuthController>().logout();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
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
      appBar: backAppBar(context, tr(context, 'account_delete_action')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AlanyaColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AlanyaColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AlanyaColors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr(context, 'account_delete_warning'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text(tr(context, 'account_delete_password'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: tr(context, 'password'),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: const TextStyle(color: AlanyaColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AlanyaColors.error),
            onPressed: _submitting ? null : _confirmAndDelete,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                : Text(tr(context, 'delete_permanently')),
          ),
        ],
      ),
    );
  }
}
