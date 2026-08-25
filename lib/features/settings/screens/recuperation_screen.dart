import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/biometric_service.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../auth/auth_repository.dart';

/// `Réglages ▸ Récupération du compte` : revoir son identifiant, ou ajouter une
/// adresse après coup.
///
/// 🔴 CET ÉCRAN EXISTE PARCE QU'UN IDENTIFIANT PERDU = UN COMPTE PERDU.
/// Il n'était montré qu'une fois, à l'inscription. Deux recours sont offerts
/// ici, et ils ne se remplacent pas : revoir le code (pour le renoter), et
/// ajouter une adresse (pour ne plus en dépendre). L'identifiant reste valable
/// après l'ajout d'une adresse.
class RecuperationScreen extends StatefulWidget {
  const RecuperationScreen({super.key});

  @override
  State<RecuperationScreen> createState() => _RecuperationScreenState();
}

class _RecuperationScreenState extends State<RecuperationScreen> {
  bool _chargement = false;

  /// L'identifiant, une fois la biométrie franchie. Nul tant qu'il n'a pas été
  /// demandé — il n'est JAMAIS chargé d'avance.
  String? _idRecuperation;
  bool _aAdresse = false;
  bool _etatCharge = false;

  @override
  void initState() {
    super.initState();
    _chargerEtat();
  }

  /// Ce que le compte possède, SANS demander le secret.
  ///
  /// ⚠️ Passe par `/api/me`, qui ne rend qu'un booléen. Appeler la route qui
  /// rend l'identifiant juste pour savoir s'il existe le ferait transiter et
  /// journaliser à chaque ouverture de cet écran, pour rien.
  Future<void> _chargerEtat() async {
    try {
      final token = await context.read<TokenStorage>().accessToken;
      if (token == null || !mounted) return;
      final moi = await context.read<AuthRepository>().me(token);
      if (!mounted) return;
      setState(() {
        _aAdresse = (moi.email ?? "").isNotEmpty;
        _etatCharge = true;
      });
    } catch (_) {
      if (mounted) setState(() => _etatCharge = true);
    }
  }

  /// Révèle l'identifiant, APRÈS confirmation biométrique.
  ///
  /// ⚠️ La biométrie n'est pas une garantie serveur — un client modifié s'en
  /// passe. Elle protège contre la menace réelle de cet écran : un téléphone
  /// déverrouillé laissé quelques secondes à portée de quelqu'un.
  ///
  /// `authenticateWithFallback` et non `authenticate` : sur un appareil sans
  /// capteur, ou dont l'empreinte ne passe pas, le code de verrouillage de
  /// l'appareil fait l'affaire. Sans repli, l'utilisateur serait enfermé
  /// dehors de son propre code de récupération.
  Future<void> _reveler() async {
    final ok = await BiometricService.authenticateWithFallback();
    if (!ok) return;
    if (!mounted) return;

    setState(() => _chargement = true);
    try {
      final token = await context.read<TokenStorage>().accessToken;
      if (token == null || !mounted) return;
      final res = await context.read<AuthRepository>().idRecuperation(token);
      if (!mounted) return;
      setState(() {
        _idRecuperation = res.idRecuperation;
        _aAdresse = res.aAdresse;
      });
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _copier() async {
    final id = _idRecuperation;
    if (id == null) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    showAppSnackBar(tr(context, 'recovery_id_copied'));
  }

  /// Ajout d'une adresse, en deux temps : demande du code, puis confirmation.
  Future<void> _ajouterAdresse() async {
    final email = await _demanderTexte(
      titre: tr(context, 'add_email_title'),
      corps: tr(context, 'add_email_body'),
      libelle: tr(context, 'email'),
      clavier: TextInputType.emailAddress,
    );
    if (email == null || !mounted) return;

    setState(() => _chargement = true);
    try {
      final token = await context.read<TokenStorage>().accessToken;
      if (token == null || !mounted) return;
      await context.read<AuthRepository>().demanderAjoutEmail(token, email);
      if (!mounted) return;
      setState(() => _chargement = false);

      final code = await _demanderTexte(
        titre: tr(context, 'confirmation'),
        corps: tr(context, 'code_sent_to').replaceFirst('{email}', email),
        libelle: tr(context, 'enter_code'),
        clavier: TextInputType.number,
        longueurMax: 6,
      );
      if (code == null || !mounted) return;

      setState(() => _chargement = true);
      await context.read<AuthRepository>().confirmerAjoutEmail(token, email, code);
      if (!mounted) return;
      showAppSnackBar(tr(context, 'add_email_done'));
      // L'état est REDEMANDÉ au serveur plutôt que deviné : c'est lui qui a
      // écrit l'adresse, et c'est lui qui dit ce que le compte porte désormais.
      await _chargerEtat();
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<String?> _demanderTexte({
    required String titre,
    required String corps,
    required String libelle,
    required TextInputType clavier,
    int? longueurMax,
  }) async {
    final ctrl = TextEditingController();
    final saisie = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(corps, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: clavier,
              maxLength: longueurMax,
              autofocus: true,
              decoration: InputDecoration(
                labelText: libelle,
                counterText: "",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: Text(tr(d, 'cancel')),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.of(d).pop(v);
            },
            child: Text(tr(d, 'continue')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return saisie;
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    final id = _idRecuperation;

    return Scaffold(
      appBar: backAppBar(context, tr(context, 'security_recovery_id')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (id != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${id.substring(0, 5)} ${id.substring(5)}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    fontFamily: "monospace",
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _copier,
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(tr(context, 'recovery_id_copy')),
              ),
            ] else if (_etatCharge && _aAdresse && !_chargement) ...[
              // Compte ouvert AVEC une adresse : il n'a pas d'identifiant, et
              // ce n'est pas une anomalie. On le dit plutôt que d'offrir un
              // bouton qui ne révélerait rien.
              Text(
                tr(context, 'recovery_id_none'),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            ] else ...[
              Text(
                tr(context, 'security_recovery_id_sub'),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _chargement ? null : _reveler,
                icon: const Icon(Icons.fingerprint),
                label: Text(tr(context, 'recovery_id_unlock')),
              ),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),

            // Second recours : ajouter une adresse. Proposé UNIQUEMENT si le
            // compte n'en a pas — le serveur refuse de remplacer une adresse
            // existante, montrer l'entrée mènerait droit à une erreur.
            if (_etatCharge && !_aAdresse)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alternate_email),
                title: Text(tr(context, 'security_add_email')),
                subtitle: Text(tr(context, 'security_add_email_sub')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _chargement ? null : _ajouterAdresse,
              ),
          ],
        ),
      ),
    );
  }
}
