import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_controller.dart';
import '../../../core/pays_repository.dart';
import '../../../core/telephone.dart';
import '../auth_repository.dart';
import 'id_recuperation_screen.dart';

/* 🔴 LA LISTE DE PAYS CODÉE EN DUR A ÉTÉ RETIRÉE LE 25/08/2026.
 *
 * Elle portait 25 pays avec des identifiants INVENTÉS — elle disait
 * « 1 = Cameroun » quand la table `pays` dit « 1 = Afrique du Sud ». Chaque
 * compte créé depuis cet écran enregistrait donc un pays faux : 4 comptes en
 * Afrique du Sud en production, tous censés être au Cameroun.
 *
 * Le serveur ne pouvait rien détecter — son contrôle demande « cet identifiant
 * existe-t-il ? », et la réponse était oui ; il désignait simplement un autre
 * pays.
 *
 * Son commentaire d'origine disait qu'elle « évite un appel API non
 * authentifié » : c'était la vraie raison, et le vrai correctif était donc
 * d'ouvrir la route. `GET /api/pays` est publique depuis le 25/08/2026 — une
 * table de référence sans donnée personnelle n'avait rien à protéger. La liste
 * vient désormais de `core/pays_repository.dart`.
 */

/// Étape 3 : choix du pseudo + mot de passe + pays. Affiche le numéro public attribué.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.setupToken,
    required this.publicNumber,
    this.idRecuperation,
  });
  final String setupToken;
  final String publicNumber;

  /// Le code de récupération d'une inscription SANS adresse, à présenter une
  /// fois le compte terminé. `null` pour une inscription par courriel.
  ///
  /// 🔴 IL EST MONTRÉ ICI, EN DERNIER (demande du user, 25/08/2026), et plus
  /// juste après la création du compte. Cet écran est le seul à savoir quand
  /// l'inscription est réellement finie : le mot de passe posé et la session
  /// obtenue. Le montrer plus tôt en faisait une étape à traverser, au milieu
  /// d'un parcours dont l'utilisateur ne voyait pas encore le bout.
  final String? idRecuperation;

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

  /// La table de référence, chargée depuis le serveur.
  ///
  /// 🔴 REMPLACE UNE LISTE CODÉE EN DUR AUX IDENTIFIANTS INVENTÉS. Elle disait
  /// « 1 = Cameroun » quand la table dit « 1 = Afrique du Sud » : chaque compte
  /// créé ici enregistrait un pays faux. Voir `core/pays_repository.dart`.
  List<Pays> _pays = const [];
  bool _paysErreur = false;

  /// Le pays choisi, ou `null`. Sert à l'indicatif et au format du numéro.
  Pays? get _paysChoisi {
    final id = _selectedPaysId;
    if (id == null) return null;
    for (final p in _pays) {
      if (p.idPays == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _chargerPays();
  }

  Future<void> _chargerPays() async {
    try {
      final liste = await context.read<PaysRepository>().liste();
      if (!mounted) return;
      setState(() => _pays = liste);
    } catch (_) {
      // On ne bloque pas l'inscription : le champ reste vide et son texte
      // d'aide le dit. Mieux vaut un compte sans pays qu'un parcours interrompu
      // au dernier écran par une table de référence indisponible.
      if (mounted) setState(() => _paysErreur = true);
    }
  }

  /// Reformate le champ téléphone avec l'indicatif du pays courant.
  ///
  /// ⚠️ Le champ affiche la forme LISIBLE (« +237 6 91 23 45 67 ») ; c'est la
  /// forme canonique qui part au serveur, et c'est le SERVEUR qui normalise en
  /// dernier ressort. Cette mise en forme n'est qu'un confort de saisie.
  void _reformaterTelephone() {
    final p = _paysChoisi;
    if (p == null) return;
    final brut = _mobileCtrl.text.trim();
    if (brut.isEmpty) return;
    final joli = formaterTelephone(brut, p.prefix, p.iso2);
    if (joli.isNotEmpty && joli != brut) {
      _mobileCtrl.value = TextEditingValue(
        text: joli,
        // Le curseur va à la FIN : le laisser où il était le placerait au
        // milieu des espaces qu'on vient d'insérer.
        selection: TextSelection.collapsed(offset: joli.length),
      );
    }
  }

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

      /*
       * DERNIÈRE ÉTAPE DE L'INSCRIPTION SANS ADRESSE : le code de récupération.
       *
       * ⚠️ AVANT `completeSetup`, et c'est délibéré. Ouvrir la session d'abord
       * ferait basculer la racine de l'application sur l'accueil, et cet écran
       * apparaîtrait par-dessus un écran d'accueil en train de se construire.
       * Ici, le parcours reste une suite d'écrans, dans l'ordre.
       *
       * ⚠️ L'attente ne se termine QUE par le bouton « Continuer » de l'écran :
       * il neutralise le geste « retour » du système (`PopScope`), sans quoi on
       * pourrait renvoyer le code d'un balayage.
       *
       * Le compte est déjà créé et son mot de passe posé à ce stade : quelqu'un
       * qui fermerait l'application ici ne perd rien — il se connecte avec son
       * numéro et retrouve le code dans `Réglages ▸ Sécurité`.
       */
      final codeRecuperation = widget.idRecuperation;
      if (codeRecuperation != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ecran) => IdRecuperationScreen(
              idRecuperation: codeRecuperation,
              publicNumber: widget.publicNumber,
              // `ecran` et non le `context` de l'écran de profil : c'est la
              // route qu'on vient de pousser qu'il faut refermer.
              onContinuer: () => Navigator.of(ecran).pop(),
            ),
          ),
        );
        if (!mounted) return;
      }

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
                  /*
                   * Mise en forme à la SORTIE du champ, pas à chaque frappe.
                   *
                   * ⚠️ Reformater pendant la saisie oblige à replacer le curseur
                   * à chaque caractère, et se bat avec l'utilisateur dès qu'il
                   * corrige au milieu de son numéro. Attendre qu'il ait fini
                   * donne le même résultat visible sans aucun de ces défauts.
                   *
                   * Ce n'est qu'un confort : c'est le SERVEUR qui normalise ce
                   * qui va en base (`src/lib/telephone.mjs`).
                   */
                  onTapOutside: (_) => _reformaterTelephone(),
                  onEditingComplete: _reformaterTelephone,
                  decoration: InputDecoration(
                    labelText: "Téléphone",
                    // L'exemple suit le pays choisi : « Ex: 690 00 00 00 » n'a
                    // aucun sens pour quelqu'un qui vient de choisir la France.
                    hintText: _paysChoisi == null
                        ? "Ex: 690 00 00 00"
                        : "${_paysChoisi!.prefix} …",
                    counterText: "",
                    prefixIcon: const Icon(Icons.phone_outlined),
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
                  isExpanded: true, // 67 pays : certains libellés sont longs.
                  decoration: InputDecoration(
                    labelText: "Pays",
                    prefixIcon: const Icon(Icons.public_outlined),
                    // Tant que la liste arrive, on le dit plutôt que d'afficher
                    // un menu vide qui ressemble à une panne.
                    helperText: _paysErreur
                        ? tr(context, 'server_unreachable')
                        : (_pays.isEmpty ? tr(context, 'loading') : null),
                  ),
                  items: _pays
                      .map((p) => DropdownMenuItem(
                            value: p.idPays,
                            child: Text(
                              "${p.drapeau}  ${p.libelle}  (${p.prefix})",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedPaysId = v;
                    // Le numéro déjà saisi est reformaté avec le nouvel
                    // indicatif : changer de pays après avoir tapé son numéro
                    // laisserait sinon un affichage qui ment sur ce qui partira.
                    _reformaterTelephone();
                  }),
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
