import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/pays_repository.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/dialogue_mot_de_passe.dart';
import '../../account/account_repository.dart';
import '../../auth/auth_repository.dart';
import 'numero_screen.dart';

/// `Réglages ▸ Pays et téléphone`.
///
/// 🔴 CET ÉCRAN NE TOUCHE JAMAIS À L'ALANYA ID, et le serveur le refuserait de
/// toute façon — sa route de profil écrit par liste blanche. Ce qu'il change,
/// ce sont deux informations distinctes :
///   - le PAYS du compte, sans mot de passe : il ne protège rien à lui seul ;
///   - le NUMÉRO DE LIGNE, derrière le mot de passe — `users.mobile` est unique
///     et sert à retrouver quelqu'un.
///
/// ⚠️ CHANGER DE PAYS NE TOUCHE PAS AU NUMÉRO (demandé deux fois par le user).
/// Un numéro appartient à l'opérateur qui l'a attribué, pas au pays où l'on
/// vit : déménager en gardant sa ligne est le cas normal.
///
/// La saisie du numéro vit dans [NumeroScreen], pas ici, et c'est le mot de
/// passe qui y donne accès : demandé À L'ENTRÉE plutôt qu'au moment
/// d'enregistrer, il évite de faire remplir un écran pour le refuser ensuite.
class PaysMobileScreen extends StatefulWidget {
  const PaysMobileScreen({super.key});

  @override
  State<PaysMobileScreen> createState() => _PaysMobileScreenState();
}

class _PaysMobileScreenState extends State<PaysMobileScreen> {
  List<Pays> _pays = const [];

  /// Le pays du COMPTE — là où vit la personne.
  int? _idPays;

  /// Remet le sélecteur de pays en accord avec [_idPays].
  ///
  /// ⚠️ `initialValue` rend le champ NON PILOTÉ : il garde ce que l'utilisateur
  /// a choisi, même si l'enregistrement a échoué. Sans ce forçage, un refus du
  /// serveur laissait affiché un pays qui n'est PAS celui du compte — et
  /// l'écran mentait sur l'état réel. Changer la clé recrée le champ, qui
  /// repart alors de l'état.
  int _cleePays = 0;

  String? _mobileActuel;

  bool _chargement = true;
  bool _envoiPays = false;

  @override
  void initState() {
    super.initState();
    _charger();
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
      // Le pays n'a pas changé en base : le sélecteur doit revenir dessus.
      if (mounted) setState(() => _cleePays++);
      showAppSnackBar(e.message);
    } catch (_) {
      if (mounted) setState(() => _cleePays++);
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _envoiPays = false);
    }
  }

  /// Le mot de passe, puis l'écran de saisie.
  ///
  /// ⚠️ Le mot de passe est vérifié AVANT l'ouverture, et transporté jusqu'à
  /// l'enregistrement parce que le serveur le redemande pour son propre compte.
  /// Il n'est jamais rangé ailleurs que dans la pile de cet appel.
  Future<void> _ouvrirNumero() async {
    final depot = context.read<AccountRepository>();
    final motDePasse = await demanderMotDePasse(
      context,
      message: tr(context, 'phone_change_explain'),
      verifier: depot.verifierMotDePasse,
    );
    if (motDePasse == null || !mounted) return;

    final nouveau = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => NumeroScreen(
          motDePasse: motDePasse,
          pays: _pays,
          idPaysInitial: _idPays,
          mobileActuel: _mobileActuel,
        ),
      ),
    );
    if (nouveau == null || !mounted) return;
    setState(() => _mobileActuel = nouveau);
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    final accent = accentOf(context);

    return Scaffold(
      appBar: backAppBar(context, tr(context, 'settings_country_phone')),
      body: SafeArea(
        child: _chargement
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Le pays du compte ────────────────────────────────────
                  Text(tr(context, 'country'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    // La clé porte l'état : elle change quand un enregistrement
                    // échoue, pour que le champ reparte du pays réel du compte.
                    key: ValueKey("pays-compte-$_cleePays-$_idPays"),
                    initialValue: _idPays,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.public_outlined),
                      helperText: tr(context, 'country_no_phone_change'),
                      helperMaxLines: 2,
                    ),
                    items: _pays
                        .map((p) => DropdownMenuItem(
                              value: p.idPays,
                              child: Text("${p.libelle}  (${p.prefix})",
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

                  // ── Le numéro : une ligne, pas un formulaire ─────────────
                  //
                  // Elle AFFICHE le numéro courant — c'est la première chose
                  // qu'on vient vérifier ici — et le changement se fait
                  // derrière, dans un écran dédié.
                  Text(tr(context, 'phone'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _ouvrirNumero,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          // Le filet du thème : celui des champs juste
                          // au-dessus, pour que la ligne appartienne à la
                          // même famille visuelle qu'eux.
                          border: Border.all(
                              color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.phone_outlined, color: muted, size: 22),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                // Rien plutôt qu'un tiret : un compte sans
                                // numéro doit inviter à en mettre un, pas
                                // afficher un vide qui ressemble à une panne.
                                (_mobileActuel == null || _mobileActuel!.isEmpty)
                                    ? tr(context, 'phone_none')
                                    : _mobileActuel!,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: (_mobileActuel == null ||
                                          _mobileActuel!.isEmpty)
                                      ? muted
                                      : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.chevron_right, color: accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
