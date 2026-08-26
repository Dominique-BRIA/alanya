import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/pays_repository.dart';
import '../../../core/telephone.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../account/account_repository.dart';

import '../../auth/auth_repository.dart';

/// `Réglages ▸ Pays et téléphone`.
///
/// 🔴 CET ÉCRAN NE TOUCHE JAMAIS À L'ALANYA ID. Il est rappelé en tête, en
/// lecture seule, précisément pour lever le doute : c'est le numéro attribué à
/// l'inscription, celui que les contacts ont enregistré et par lequel on
/// appelle. Rien ici ne peut le changer, et le serveur le refuserait de toute
/// façon — sa route de profil écrit par liste blanche.
///
/// Ce que l'écran change, ce sont deux informations distinctes :
///   - le PAYS du compte, sans mot de passe : il ne protège rien à lui seul ;
///   - le NUMÉRO DE LIGNE, sous mot de passe — `users.mobile` est unique et
///     sert à retrouver quelqu'un.
///
/// ⚠️ LE PAYS EST PLACÉ AU-DESSUS DU NUMÉRO, et ce n'est pas cosmétique : c'est
/// l'indicatif du pays du compte qui sert à normaliser un numéro saisi sans
/// « + ». Changer le pays d'abord donne le bon indicatif au numéro qui suit.
class PaysMobileScreen extends StatefulWidget {
  const PaysMobileScreen({super.key});

  @override
  State<PaysMobileScreen> createState() => _PaysMobileScreenState();
}

class _PaysMobileScreenState extends State<PaysMobileScreen> {
  final _mobileCtrl = TextEditingController();
  final _mdpCtrl = TextEditingController();

  List<Pays> _pays = const [];
  int? _idPays;
  String? _mobileActuel;
  String? _alanyaId;

  bool _chargement = true;
  bool _envoiPays = false;
  bool _envoiMobile = false;

  Pays? get _paysChoisi {
    final id = _idPays;
    if (id == null) return null;
    for (final p in _pays) {
      if (p.idPays == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    _mdpCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final liste = await context.read<PaysRepository>().liste();
      if (!mounted) return;
      final jeton = await context.read<TokenStorage>().accessToken;
      if (jeton == null || !mounted) return;
      // Le profil est relu au SERVEUR plutôt que pris dans le cache : c'est lui
      // qui fait foi sur le pays et le numéro, et l'écran sert justement à les
      // changer — partir d'une valeur périmée ferait afficher l'ancienne.
      final moi = await context.read<AuthRepository>().me(jeton);
      if (!mounted) return;
      setState(() {
        _pays = liste;
        _idPays = moi.idPays;
        _mobileActuel = moi.mobile;
        _alanyaId = moi.publicNumber;
        _mobileCtrl.text = moi.mobile ?? "";
        _chargement = false;
      });
    } catch (_) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _enregistrerPays(int id) async {
    setState(() => _envoiPays = true);
    try {
      await context.read<AccountRepository>().changerPays(id);
      if (!mounted) return;
      setState(() => _idPays = id);
      showAppSnackBar(tr(context, 'country_saved'));
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _envoiPays = false);
    }
  }

  Future<void> _enregistrerMobile() async {
    final numero = _mobileCtrl.text.trim();
    final mdp = _mdpCtrl.text;
    if (numero.isEmpty) {
      showAppSnackBar(tr(context, 'phone_required'));
      return;
    }
    if (mdp.isEmpty) {
      showAppSnackBar(tr(context, 'password_required'));
      return;
    }

    setState(() => _envoiMobile = true);
    try {
      final enregistre = await context
          .read<AccountRepository>()
          .changerMobile(motDePasse: mdp, mobile: numero);
      if (!mounted) return;
      setState(() {
        _mobileActuel = enregistre;
        // Le champ reprend la forme RETENUE PAR LA BASE, pas la saisie : sans
        // ça, l'écran continuerait d'afficher « 06 12 34 56 78 » alors que le
        // compte porte « +33612345678 ».
        _mobileCtrl.text = enregistre;
        // Le mot de passe est effacé dès l'opération finie : le garder en
        // mémoire de l'écran n'apporte rien et l'expose.
        _mdpCtrl.clear();
      });
      showAppSnackBar(tr(context, 'phone_saved'));
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _envoiMobile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);

    return Scaffold(
      appBar: backAppBar(context, tr(context, 'settings_country_phone')),
      body: SafeArea(
        child: _chargement
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── L'Alanya ID, EN LECTURE SEULE ────────────────────────
                  //
                  // Rappelé ici pour lever le doute : c'est le numéro de
                  // l'inscription, et rien sur cet écran ne le change.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: accentOf(context).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.badge_outlined, color: accentOf(context)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr(context, 'alanya_number'),
                                  style: TextStyle(color: muted, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(
                                _alanyaId == null
                                    ? "—"
                                    : formatAlanyaId(_alanyaId!),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(tr(context, 'alanya_number_fixed'),
                                  style: TextStyle(color: muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Le pays ──────────────────────────────────────────────
                  Text(tr(context, 'country'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _idPays,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.public_outlined),
                      helperText: tr(context, 'country_no_phone_change'),
                      helperMaxLines: 2,
                    ),
                    items: _pays
                        .map((p) => DropdownMenuItem(
                              value: p.idPays,
                              child: Text("${p.drapeau}  ${p.libelle}  (${p.prefix})",
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _envoiPays
                        ? null
                        : (v) {
                            if (v != null) _enregistrerPays(v);
                          },
                  ),
                  const SizedBox(height: 28),

                  // ── Le numéro ────────────────────────────────────────────
                  Text(tr(context, 'phone'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(tr(context, 'phone_change_explain'),
                      style: TextStyle(color: muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _mobileCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: tr(context, 'phone'),
                      prefixIcon: const Icon(Icons.phone_outlined),
                      counterText: "",
                      // L'exemple suit le pays choisi : « 690 00 00 00 » n'a
                      // aucun sens pour quelqu'un qui vient de choisir la France.
                      hintText: _paysChoisi == null ? null : "${_paysChoisi!.prefix} …",
                    ),
                    // Mise en forme à la SORTIE du champ, pas à chaque frappe :
                    // reformater pendant la saisie oblige à replacer le curseur
                    // à chaque caractère.
                    onTapOutside: (_) => _reformater(),
                    onEditingComplete: _reformater,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mdpCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: tr(context, 'current_password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _envoiMobile ? null : _enregistrerMobile,
                    child: Text(tr(context, 'save')),
                  ),

                  if (_mobileActuel != null && _mobileActuel!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'phone_current')
                          .replaceFirst('{number}', _mobileActuel!),
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  /// Met en forme le champ avec l'indicatif du pays courant.
  ///
  /// ⚠️ Confort de saisie SEULEMENT — c'est le serveur qui normalise ce qui va
  /// en base, et lui qui respecte un « + » initial pour une ligne étrangère.
  void _reformater() {
    final p = _paysChoisi;
    if (p == null) return;
    final brut = _mobileCtrl.text.trim();
    if (brut.isEmpty) return;
    final joli = formaterTelephone(brut, p.prefix, p.iso2);
    if (joli.isNotEmpty && joli != brut) {
      _mobileCtrl.value = TextEditingValue(
        text: joli,
        selection: TextSelection.collapsed(offset: joli.length),
      );
    }
  }
}
