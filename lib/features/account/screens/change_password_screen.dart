import 'package:flutter/material.dart';
import '../../../services/e2ee/e2ee_fournisseur.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../core/device_registry.dart';
import '../../../core/realtime_client.dart';
import '../../../core/token_storage.dart';
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
  bool _deconnecterAutres = false;
  /*
   * 🔴 LA CASE SE BLOQUE QUAND L'ARCHIVE EST FERMÉE ICI (27/11/2026). Les
   * autres appareils gardent peut-être la seule copie de la clé : les
   * déconnecter pourrait vider leur coffre, et l'historique serait perdu.
   */
  bool _deconnecterBloque = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sauvegarde = context.e2ee?.sauvegarde;
      if (sauvegarde == null || sauvegarde.estOuverte) return;
      final bloque = await sauvegarde.aUneArchive();
      if (mounted && bloque) {
        setState(() {
          _deconnecterBloque = true;
          _deconnecterAutres = false;
        });
      }
    });
  }

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
      final deconnecter = _deconnecterAutres && !_deconnecterBloque;
      final realtime = context.read<RealtimeClient>();
      final depot = context.read<AccountRepository>();
      // Pris avant toute attente : le contexte ne se relit plus ensuite.
      final pile = context.e2ee;
      final sauvegarde = pile?.sauvegarde;
      /*
       * 🔴 COUCHE A (27/11/2026) : la serrure du nouveau mot de passe est
       * fabriquée AVANT, et part dans la même requête. Le serveur écrit les
       * deux ensemble ; il n'y a plus rien à faire suivre après coup.
       */
      final serrure = pile == null
          ? null
          : await pile.sauvegarde.preparerSerrureMotDePasse(current, next, pile.compteId);
      final reponse = await depot.changePassword(
            current,
            next,
            deconnecterAutres: deconnecter,
            appareilCourant: await DeviceRegistry.instance.deviceId(),
            jetonCourant: deconnecter ? await TokenStorage().refreshToken : null,
            serrure: serrure?.enJson(),
          );
      final revoques = reponse.revoques;
      // Les sockets des appareils révoqués se ferment tout de suite : sans
      // cette annonce, ils garderaient le temps réel jusqu'à 15 minutes.
      for (final id in revoques) {
        realtime.sendSessionRevoked(id);
      }

      /*
       * 🐛 LA SAUVEGARDE DOIT SUIVRE, SINON ELLE CASSE EN SILENCE. Sa serrure
       * garde l'ANCIEN mot de passe tant qu'on ne la ré-enveloppe pas :
       * l'ouverture automatique échouerait à la connexion suivante, et
       * l'utilisateur le découvrirait au pire moment — en changeant d'appareil.
       *
       * ⚠️ APRÈS le changement, jamais avant : si l'API refuse, il n'y a rien à
       * ré-envelopper, et on aurait posé une serrure pour un mot de passe que le
       * compte n'a pas.
       *
       * ⚠️ RIEN N'EST RECHIFFRÉ : on ré-enveloppe 32 octets.
       */
      // Serveur d'avant la couche A, ou serrure impossible à fabriquer ici.
      final suivi = reponse.serrurePosee ||
          (await sauvegarde?.suivreChangementMotDePasse(next) ?? true);
      if (!mounted) return;
      /*
       * 🔴 UN ÉCHEC SE DIT (27/11/2026). Il passait sous silence, et l'on
       * découvrait l'archive fermée au changement d'appareil. Seulement s'il y
       * a une archive : sans elle, il n'y avait rien à faire suivre. La
       * prochaine connexion sur cet appareil la répare.
       */
      if (!suivi && sauvegarde != null && await sauvegarde.aUneArchive()) {
        // Les appareils qui ont la clé affichent le bandeau de la couche B.
        realtime.sendSignalSauvegarde('serrure_perimee');
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(tr(ctx, 'arch_suivi_echoue')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
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
          const SizedBox(height: 16),
          // « Déconnecter mes autres appareils » (27/11/2026) : facultatif,
          // cet appareil reste connecté.
          CheckboxListTile(
            value: _deconnecterAutres,
            onChanged: _submitting || _deconnecterBloque
                ? null
                : (v) => setState(() => _deconnecterAutres = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(tr(context, 'arch_deconnecter_autres')),
            subtitle: Text(tr(
              context,
              _deconnecterBloque ? 'arch_deconnecter_bloque' : 'arch_deconnecter_autres_d',
            )),
          ),
          const SizedBox(height: 20),
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
