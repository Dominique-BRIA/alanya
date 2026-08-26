import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/pays_repository.dart';
import '../../../core/telephone.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../account/account_repository.dart';
import 'choix_pays_screen.dart';

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
  final _numeroFocus = FocusNode();

  int? _idPays;
  bool _envoi = false;

  Pays? get _paysChoisi {
    final id = _idPays;
    if (id == null) return null;
    for (final p in widget.pays) {
      if (p.idPays == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _idPays = widget.idPaysInitial;
    _preremplir();
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _numeroFocus.dispose();
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

  Future<void> _choisirPays() async {
    final choisi = await Navigator.of(context).push<Pays>(
      MaterialPageRoute(
        builder: (_) => ChoixPaysScreen(
          pays: widget.pays,
          idSelectionne: _idPays,
        ),
      ),
    );
    if (choisi == null || !mounted) return;
    setState(() => _idPays = choisi.idPays);
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
    final complet = normaliserTelephone(saisi, pays.prefix);

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
    final accent = accentOf(context);
    final muted = mutedOf(context, Colors.black54);
    final pays = _paysChoisi;

    // Soulignement seul, sans remplissage : c'est ce qui donne à l'écran son
    // allure de saisie de numéro plutôt que de formulaire de réglages. Le
    // thème global remplit et arrondit les champs — il est écarté ici, et
    // seulement ici.
    InputDecoration souligne({String? hint}) => InputDecoration(
          hintText: hint,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: accent.withValues(alpha: 0.45)),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: accent, width: 2),
          ),
          border: const UnderlineInputBorder(),
        );

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

            // ── Le pays, sur sa propre ligne ──────────────────────────────
            InkWell(
              onTap: _envoi ? null : _choisirPays,
              child: InputDecorator(
                decoration: souligne(),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pays?.libelle ?? tr(context, 'choose_country'),
                        style: TextStyle(
                          fontSize: 16,
                          color: pays == null ? muted : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: accent),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── L'indicatif, puis le numéro ───────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // L'indicatif est AFFICHÉ, pas saisi : il suit le pays choisi
                // au-dessus. Le rendre modifiable ouvrirait la porte à un
                // indicatif qui contredit le pays, et il faudrait alors
                // décider lequel des deux fait foi.
                SizedBox(
                  width: 76,
                  child: InputDecorator(
                    decoration: souligne(),
                    child: Text(
                      pays == null || pays.prefix.isEmpty ? "+" : pays.prefix,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _numeroCtrl,
                    focusNode: _numeroFocus,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    maxLength: 20,
                    style: const TextStyle(fontSize: 16),
                    // Le champ ne prend QUE des chiffres : l'indicatif est
                    // dans la case de gauche, et un « + » tapé ici produirait
                    // un numéro à deux indicatifs.
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: souligne(hint: tr(context, 'phone_hint'))
                        .copyWith(counterText: ""),
                  ),
                ),
              ],
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
