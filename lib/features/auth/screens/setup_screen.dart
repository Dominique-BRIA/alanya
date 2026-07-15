import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_controller.dart';
import '../auth_repository.dart';

/// Données pays statiques pour l'inscription (évite un appel API non authentifié).
class _PaysOption {
  final int id;
  final String flag;
  final String nom;
  final String prefix;
  const _PaysOption(this.id, this.flag, this.nom, this.prefix);
}

const _paysList = [
  _PaysOption(1, "🇨🇲", "Cameroun", "+237"),
  _PaysOption(2, "🇫🇷", "France", "+33"),
  _PaysOption(3, "🇨🇮", "Côte d'Ivoire", "+225"),
  _PaysOption(4, "🇸🇳", "Sénégal", "+221"),
  _PaysOption(5, "🇨🇩", "RD Congo", "+243"),
  _PaysOption(6, "🇬🇦", "Gabon", "+241"),
  _PaysOption(7, "🇹🇩", "Tchad", "+235"),
  _PaysOption(8, "🇨🇬", "Congo", "+242"),
  _PaysOption(9, "🇧🇯", "Bénin", "+229"),
  _PaysOption(10, "🇹🇬", "Togo", "+228"),
  _PaysOption(11, "🇲🇱", "Mali", "+223"),
  _PaysOption(12, "🇧🇫", "Burkina Faso", "+226"),
  _PaysOption(13, "🇳🇪", "Niger", "+227"),
  _PaysOption(14, "🇬🇳", "Guinée", "+224"),
  _PaysOption(15, "🇲🇦", "Maroc", "+212"),
  _PaysOption(16, "🇩🇿", "Algérie", "+213"),
  _PaysOption(17, "🇹🇳", "Tunisie", "+216"),
  _PaysOption(18, "🇳🇬", "Nigeria", "+234"),
  _PaysOption(19, "🇬🇭", "Ghana", "+233"),
  _PaysOption(20, "🇨🇦", "Canada", "+1"),
  _PaysOption(21, "🇧🇪", "Belgique", "+32"),
  _PaysOption(22, "🇨🇭", "Suisse", "+41"),
  _PaysOption(23, "🇩🇪", "Allemagne", "+49"),
  _PaysOption(24, "🇬🇧", "Royaume-Uni", "+44"),
  _PaysOption(25, "🇺🇸", "États-Unis", "+1"),
];

/// Étape 3 : choix du pseudo + mot de passe + pays. Affiche le numéro public attribué.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.setupToken, required this.publicNumber});
  final String setupToken;
  final String publicNumber;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _pseudoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  int? _selectedPaysId;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _pseudoCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final session = await context.read<AuthRepository>().setup(
            setupToken: widget.setupToken,
            pseudo: _pseudoCtrl.text.trim(),
            password: _passwordCtrl.text,
            nom: _nomCtrl.text.trim().isNotEmpty ? _nomCtrl.text.trim() : null,
            idPays: _selectedPaysId,
          );
      if (!mounted) return;
      await context.read<AuthController>().completeSetup(session);
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
      appBar: backAppBar(context, tr(context, 'profile_setup')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Carte affichant le numéro public attribué
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AlanyaColors.terracotta.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AlanyaColors.terracotta.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        tr(context, 'alanya_number'),
                        style: const TextStyle(color: AlanyaColors.chocolate),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.publicNumber,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                          color: AlanyaColors.terracotta,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'alanya_number_help'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // --- Nom ---
                TextFormField(
                  controller: _nomCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Nom",
                    hintText: "Ex: BRIA",
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                // --- Pseudo ---
                TextFormField(
                  controller: _pseudoCtrl,
                  decoration: InputDecoration(
                    labelText: tr(context, 'pseudo'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v ?? "").trim().length < 2 ? "Pseudo trop court" : null,
                ),
                const SizedBox(height: 16),

                // --- Pays ---
                DropdownButtonFormField<int>(
                  value: _selectedPaysId,
                  decoration: const InputDecoration(
                    labelText: "Pays",
                    prefixIcon: Icon(Icons.public_outlined),
                  ),
                  items: _paysList.map((p) {
                    return DropdownMenuItem(
                      value: p.id,
                      child: Text("${p.flag}  ${p.nom}  (${p.prefix})"),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedPaysId = v),
                ),
                const SizedBox(height: 16),

                // --- Mot de passe ---
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
                  validator: (v) =>
                      (v ?? "").length < 8 ? tr(context, 'password_min_8') : null,
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
                      : Text(tr(context, 'finish')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
