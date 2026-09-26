import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/pays_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../account/account_repository.dart';
import '../../../widgets/saisie_pays_numero.dart';

/// Saisir son numéro de téléphone : le pays d'abord, le numéro ensuite.
///
/// Disposition demandée par le user le 26/08/2026 — celle de l'inscription
/// WhatsApp : un pays sur sa ligne, puis l'indicatif et le numéro côte à côte,
/// soulignés. Elle vaut mieux qu'un formulaire parce qu'elle rend l'ordre des
/// gestes évident : l'indicatif s'affiche à gauche du champ AVANT qu'on tape, et
/// on voit donc le numéro qu'on est en train de composer, en entier.
///
/// 🔴 PAS D'ALANYA ID ICI, ET AUCUN RISQUE D'EN TOUCHER UN. Cet écran n'écrit
/// que `users.mobile`, le numéro de ligne déclaré. L'Alanya ID est l'identité du
/// compte — ce que les contacts ont enregistré, ce qu'on compose pour appeler —
/// et il ne change jamais.
///
/// 🔴 LE PAYS CHOISI ICI EST CELUI DE LA LIGNE, PAS CELUI DU COMPTE. Il n'est
/// écrit nulle part : il ne sert qu'à donner son indicatif au numéro. On vit
/// dans un pays en gardant une ligne d'un autre, et c'est la raison même pour
/// laquelle changer de pays ne touche pas au numéro.
///
/// ⚠️ [motDePasse] a DÉJÀ été vérifié par l'écran appelant — on n'arrive pas
/// ici sans. Il est reporté jusqu'à l'enregistrement parce que le serveur le
/// redemande pour son propre compte : une porte côté client ne protège rien,
/// c'est le contrôle au moment d'écrire qui compte.
class NumeroScreen extends StatefulWidget {
  const NumeroScreen({
    super.key,
    required this.motDePasse,
    required this.pays,
    this.idPaysInitial,
    this.mobileActuel,
  });

  final String motDePasse;
  final List<Pays> pays;

  /// Le pays du compte, comme point de départ : c'est le cas le plus fréquent.
  final int? idPaysInitial;

  final String? mobileActuel;

  @override
  State<NumeroScreen> createState() => _NumeroScreenState();
}

class _NumeroScreenState extends State<NumeroScreen> {
  final _numeroCtrl = TextEditingController();

  int? _idPays;
  bool _envoi = false;

  Pays? get _paysChoisi => paysParId(widget.pays, _idPays);

  @override
  void initState() {
    super.initState();
    _idPays = widget.idPaysInitial;
    _preremplir();
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    super.dispose();
  }

  /// Repart du numéro actuel, mais SANS son indicatif.
  ///
  /// L'indicatif a sa propre case à gauche : le laisser dans le champ le
  /// ferait apparaître deux fois, et le numéro repartirait avec un indicatif
  /// redoublé au premier enregistrement.
  void _preremplir() {
    final actuel = widget.mobileActuel;
    if (actuel == null || actuel.isEmpty) return;

    final chiffres = actuel.replaceAll(RegExp(r"\D"), "");
    for (final p in widget.pays) {
      final ind = p.prefix.replaceAll(RegExp(r"\D"), "");
      if (ind.isEmpty || !chiffres.startsWith(ind)) continue;
      // Le pays de la LIGNE se déduit du numéro lui-même, et il est plus juste
      // que le pays du compte : quelqu'un installé à l'étranger retrouve son
      // vrai indicatif au lieu de celui de sa résidence.
      _idPays = p.idPays;
      _numeroCtrl.text = chiffres.substring(ind.length);
      return;
    }
    _numeroCtrl.text = chiffres;
  }

  Future<void> _enregistrer() async {
    final pays = _paysChoisi;
    if (pays == null) {
      showAppSnackBar(tr(context, 'country_required'));
      return;
    }
    final saisi = _numeroCtrl.text.trim();
    if (saisi.isEmpty) {
      showAppSnackBar(tr(context, 'phone_required'));
      return;
    }

    // L'indicatif est recollé ICI, parce qu'il n'est pas dans le champ : le
    // serveur normalise ensuite, avec la même règle qu'à l'inscription.
    final complet =
        SaisiePaysNumero.numeroComplet(widget.pays, pays.idPays, saisi);

    setState(() => _envoi = true);
    try {
      final enregistre = await context.read<AccountRepository>().changerMobile(
            motDePasse: widget.motDePasse,
            mobile: complet,
            idPaysNumero: pays.idPays,
          );
      if (!mounted) return;
      showAppSnackBar(tr(context, 'phone_saved'));
      Navigator.of(context).pop(enregistre);
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);

    return Scaffold(
      appBar: backAppBar(context, tr(context, 'phone_number_title')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            Text(
              tr(context, 'phone_number_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 32),

            // 🔴 LE MÊME COMPOSANT QU'À L'INSCRIPTION. Les deux écrans avaient
            // chacun leur formulaire, et c'est ainsi qu'un numéro finit stocké
            // sous deux formes dans une colonne UNIQUE.
            SaisiePaysNumero(
              pays: widget.pays,
              idPays: _idPays,
              controller: _numeroCtrl,
              onPays: (id) => setState(() => _idPays = id),
              actif: !_envoi,
              autofocus: true,
            ),
            const SizedBox(height: 40),

            FilledButton(
              onPressed: _envoi ? null : _enregistrer,
              child: _envoi
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(tr(context, 'save')),
            ),
          ],
        ),
      ),
    );
  }
}
