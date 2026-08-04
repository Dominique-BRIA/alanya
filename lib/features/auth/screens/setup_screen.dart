import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/alanya_id_formatter.dart';
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
  final _mobileCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  int? _selectedPaysId;
  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _mobileCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final session = await context.read<AuthRepository>().setup(
            setupToken: widget.setupToken,
            password: _passwordCtrl.text,
            nom: _nomCtrl.text.trim(),
            mobile: _mobileCtrl.text.trim(),
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
                    color: accentOf(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentOf(context).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        tr(context, 'alanya_number'),
                        style: TextStyle(color: alanyaIdOf(context, AlanyaColors.chocolate)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatAlanyaId(widget.publicNumber),
                        style: TextStyle(
                          // Le formatage apporte déjà des espaces : un
                          // letterSpacing de 6 par-dessus disloquait les
                          // groupes au lieu de les séparer.
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: accentOf(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'alanya_number_help'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: mutedOf(context, Colors.black54)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // --- Nom ---
                // C'est ce nom qui s'affiche partout : dans les contacts, les
                // conversations et les appels. Le pseudo n'est plus demandé —
                // le nom y est recopié à l'envoi, tronqué à 50 caractères.
                TextFormField(
                  controller: _nomCtrl,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: "Nom",
                    hintText: "Ex: BRIA Dominique",
                    counterText: "",
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  // Minimum 2 caractères, et non 1 : le nom sert de pseudo au
                  // serveur, qui en exige deux. Un nom d'une seule lettre
                  // passerait ici puis serait rejeté à l'envoi.
                  validator: (v) => (v ?? "").trim().length < 2
                      ? "Entre ton nom (2 caractères minimum)"
                      : null,
                ),
                const SizedBox(height: 16),

                // --- Téléphone ---
                TextFormField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  // Aligné sur la colonne users.mobile, en VARCHAR(20).
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: "Téléphone",
                    hintText: "Ex: 690 00 00 00",
                    counterText: "",
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    final t = (v ?? "").trim();
                    if (t.isEmpty) return "Entre ton numéro de téléphone";
                    // Au moins six chiffres : accepte les espaces, tirets et
                    // indicatifs, sans imposer un format qui varie d'un pays à
                    // l'autre.
                    final chiffres = t.replaceAll(RegExp(r'\D'), '');
                    if (chiffres.length < 6) return "Numéro de téléphone invalide";
                    return null;
                  },
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
                const SizedBox(height: 16),

                // --- Confirmation du mot de passe ---
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: "Confirmer le mot de passe",
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  // Comparaison sur la valeur brute, sans trim : un espace
                  // final fait partie du mot de passe.
                  validator: (v) {
                    if ((v ?? "").isEmpty) return "Confirme ton mot de passe";
                    if (v != _passwordCtrl.text) {
                      return "Les mots de passe ne correspondent pas";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // --- Pays ---
                // Placé en dernier : c'est le champ le moins engageant, et
                // l'utilisateur arrive au bouton juste après.
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
                  validator: (v) => v == null ? "Choisis ton pays" : null,
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
