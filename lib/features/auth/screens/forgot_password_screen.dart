import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../auth_repository.dart';
import 'nouveau_mot_de_passe_screen.dart';

/// Écran de réinitialisation de mot de passe (Mot de passe oublié).
///
/// Par ADRESSE — Étape 1 : saisie de l'email → envoi du code OTP.
///              Étape 2 : saisie du code + nouveau mot de passe, ici même.
///
/// Par CODE DE RÉCUPÉRATION — Étape 1 : le code et l'Alanya ID, ici ;
///              Étape 2 : le nouveau mot de passe et sa confirmation, sur
///              `NouveauMotDePasseScreen`, qui ne s'ouvre qu'après vérification.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  /// Le champ du code de récupération.
  ///
  /// ⚠️ SÉPARÉ de `_codeCtrl` à dessein. Les partager aurait fait traîner d'un
  /// mode à l'autre une saisie abandonnée — un code à 6 chiffres resté dans le
  /// champ du code de récupération, par exemple — et la première erreur du
  /// serveur aurait été incompréhensible.
  ///
  /// 🔴 Le mot de passe N'EST PLUS SAISI ICI : il vit sur l'écran suivant, qui
  /// ne s'ouvre qu'une fois la paire vérifiée par le serveur.
  final _idRecCtrl = TextEditingController();

  /// L'Alanya ID du compte à reprendre — SECOND FACTEUR du chemin par code.
  ///
  /// 🔴 Le code seul ne suffit plus : c'était un secret unique dont la fuite
  /// aurait ouvert tous les comptes sans adresse d'un coup. L'Alanya ID n'est
  /// pas un secret, mais il empêche la reprise en masse — un code volé ne dit
  /// plus à quel compte il appartient.
  final _idRecNumCtrl = TextEditingController();

  bool _loading = false;
  bool _codeSent = false; // Passe à true après l'envoi du code

  /// Mode de reprise choisi. Faux = par adresse (le parcours historique).
  bool _parIdRecuperation = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    _idRecCtrl.dispose();
    _idRecNumCtrl.dispose();
    super.dispose();
  }

  /// Reprise par IDENTIFIANT DE RÉCUPÉRATION — pour un compte sans adresse.
  ///
  /// 🔴 EN DEUX ÉCRANS depuis le 25/08/2026 (demande du user) : ici la PREUVE
  /// — le code et l'Alanya ID —, puis le nouveau mot de passe sur l'écran
  /// suivant. Les trois champs cohabitaient auparavant : on saisissait un mot
  /// de passe pour apprendre ensuite que le code était faux, et tout était à
  /// refaire.
  ///
  /// ⚠️ CETTE ÉTAPE N'AUTORISE RIEN et ne rapporte aucun jeton. Le serveur se
  /// contente de dire si la paire désigne un compte ; c'est la réinitialisation
  /// de l'écran suivant, qui renvoie les deux mêmes éléments, qui fait foi. Le
  /// pouvoir de reprendre le compte reste attaché à la paire.
  ///
  /// ⚠️ Elle CONSOMME un essai du plafond de reprise (5 par quart d'heure,
  /// partagé avec la réinitialisation) : une reprise réussie en coûte donc
  /// deux. C'est pourquoi elle est déclenchée par le bouton et jamais par la
  /// frappe.
  Future<void> _verifierPuisContinuer() async {
    final id = _idRecCtrl.text.trim();
    final numero = _idRecNumCtrl.text.trim();

    if (id.isEmpty) {
      showAppSnackBar(tr(context, 'recovery_id_required'));
      return;
    }
    if (numero.isEmpty) {
      showAppSnackBar(tr(context, 'recovery_alanya_id_required'));
      return;
    }

    setState(() => _loading = true);
    try {
      // La saisie part TELLE QUELLE : c'est le serveur qui relève la casse,
      // ignore les séparateurs et traduit les I/L/O mal lus. Nettoyer ici
      // ferait une seconde règle à tenir accordée avec la sienne.
      await context.read<AuthRepository>().verifierIdRecuperation(
            idRecuperation: id,
            alanyaId: numero,
          );
      if (!mounted) return;
      // Le chargement est relâché AVANT de pousser l'écran suivant : au retour
      // par le bouton « précédent », cet écran-ci doit être utilisable, et un
      // `_loading` resté vrai y laisserait un bouton mort.
      setState(() => _loading = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NouveauMotDePasseScreen(
            idRecuperation: id,
            alanyaId: numero,
          ),
        ),
      );
    } on ApiException catch (e) {
      _onError(e.message);
    } catch (_) {
      _onError("Erreur réseau. Vérifie ta connexion.");
    }
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
                  Icon(Icons.lock_reset, size: 64, color: accentOf(context)),
                  const SizedBox(height: 16),

                  /*
                   * Choix du chemin de reprise.
                   *
                   * ⚠️ MASQUÉ UNE FOIS LE CODE ENVOYÉ : changer de mode à ce
                   * moment-là abandonnerait un code déjà parti par courriel,
                   * sans le dire. On ne propose que ce qui est encore possible.
                   */
                  if (!_codeSent) ...[
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(tr(context, 'forgot_by_email')),
                          icon: const Icon(Icons.mail_outline, size: 18),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(tr(context, 'forgot_by_recovery_id')),
                          icon: const Icon(Icons.key_outlined, size: 18),
                        ),
                      ],
                      selected: {_parIdRecuperation},
                      onSelectionChanged: (s) =>
                          setState(() => _parIdRecuperation = s.first),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Text(
                    _parIdRecuperation
                        ? "Réinitialise ton mot de passe"
                        : _codeSent
                            ? "Vérifie ta boîte mail"
                            : "Réinitialise ton mot de passe",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _parIdRecuperation
                        ? tr(context, 'recovery_id_hint')
                        : _codeSent
                            ? "Saisis le code à 6 chiffres reçu par email et ton nouveau mot de passe."
                            : "Saisis ton adresse email. Si un compte existe, tu recevras un code de vérification.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedOf(context, Colors.black54)),
                  ),
                  const SizedBox(height: 32),

                  // ═══ Chemin par IDENTIFIANT DE RÉCUPÉRATION ═══
                  if (_parIdRecuperation) ...[
                    TextField(
                      controller: _idRecCtrl,
                      // Majuscules et chasse fixe : l'identifiant est stocké en
                      // majuscules, et l'utilisateur recopie un papier.
                      textCapitalization: TextCapitalization.characters,
                      // 12 et non 10 : les tirets ou espaces de relecture que
                      // l'utilisateur recopie doivent tenir dans le champ. Le
                      // serveur les ignore ; les refuser à la saisie donnerait
                      // l'impression que le code est faux.
                      maxLength: 12,
                      style: const TextStyle(
                          fontFamily: "monospace", letterSpacing: 2),
                      decoration: InputDecoration(
                        labelText: tr(context, 'recovery_id_label'),
                        prefixIcon: const Icon(Icons.key_outlined),
                        counterText: "",
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Second facteur. `keyboardType: number` mais SANS filtre
                    // sur les chiffres : l'Alanya ID est affiché formaté par
                    // paires dans toute l'application, et c'est sous cette
                    // forme que l'utilisateur le connaît. Le serveur ne retient
                    // que les chiffres — refuser les espaces à la saisie
                    // rejetterait la façon la plus naturelle de le recopier.
                    TextField(
                      controller: _idRecNumCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr(context, 'recovery_alanya_id_label'),
                        helperText: tr(context, 'recovery_alanya_id_hint'),
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                    ),
                    // 🔴 PAS DE CHAMP « nouveau mot de passe » ICI. Il vit sur
                    // `NouveauMotDePasseScreen`, avec sa confirmation, et cet
                    // écran-ci ne s'occupe que de la preuve.
                  ],

                  // ═══ Chemin par ADRESSE (historique) ═══
                  if (!_parIdRecuperation)
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
                  if (_codeSent && !_parIdRecuperation) ...[
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
                          : _parIdRecuperation
                              ? _verifierPuisContinuer
                              : _codeSent
                                  ? _resetPassword
                                  : _sendCode,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          // « Continuer » et non « Réinitialiser » sur le
                          // chemin par code : rien n'est encore changé à cet
                          // appui, le mot de passe se pose à l'écran suivant.
                          // Annoncer « Réinitialiser » ferait croire l'affaire
                          // faite à qui s'arrêterait là.
                          : Text(_parIdRecuperation
                              ? tr(context, 'continue')
                              : _codeSent
                                  ? "Réinitialiser"
                                  : "Envoyer le code"),
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
