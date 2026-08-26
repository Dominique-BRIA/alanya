import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_controller.dart';
import '../../../core/pays_repository.dart';
import '../auth_repository.dart';
import '../../../widgets/saisie_pays_numero.dart';
import 'fin_inscription_screen.dart';

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

  /// Le pays choisi, ou `null`. C'est lui qui donne l'indicatif au numéro.
  Pays? get _paysChoisi => paysParId(_pays, _selectedPaysId);

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

  @override
  void dispose() {
    _nomCtrl.dispose();
    _mobileCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Le pays et le numéro sont-ils utilisables ?
  ///
  /// 🔴 CONTRÔLE EXPLICITE, PARCE QUE LE BLOC N'EST PAS UN `FormField`. Les deux
  /// champs étaient auparavant des `TextFormField` et un `DropdownButtonFormField`
  /// avec leurs `validator` : `_formKey.currentState.validate()` les couvrait.
  /// Le composant partagé, lui, n'est pas rattaché au formulaire — sans ce
  /// contrôle, l'inscription partait avec un numéro vide et la validation avait
  /// disparu sans que rien ne le signale.
  String? _erreurPaysNumero() {
    if (_paysChoisi == null) return tr(context, 'country_required');
    // Au moins six chiffres : le champ n'accepte déjà que des chiffres, et une
    // longueur fixe varie trop d'un pays à l'autre pour être imposée ici.
    final chiffres = _mobileCtrl.text.replaceAll(RegExp(r"\D"), "");
    if (chiffres.isEmpty) return tr(context, 'phone_required');
    if (chiffres.length < 6) return tr(context, 'phone_invalid');
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final souci = _erreurPaysNumero();
    if (souci != null) {
      showAppSnackBar(souci);
      return;
    }
    setState(() => _loading = true);
    try {
      final session = await context.read<AuthRepository>().setup(
            setupToken: widget.setupToken,
            password: _passwordCtrl.text,
            nom: _nomCtrl.text.trim(),
            // L'indicatif est recollé ici : il n'est pas dans le champ, il est
            // dans sa propre case à gauche.
            mobile: SaisiePaysNumero.numeroComplet(
                _pays, _selectedPaysId, _mobileCtrl.text),
            idPays: _selectedPaysId,
          );
      if (!mounted) return;

      /*
       * DERNIÈRE ÉTAPE DE L'INSCRIPTION : l'Alanya ID, et le code de
       * récupération quand le compte n'a pas d'adresse.
       *
       * 🔴 CET ÉCRAN S'AFFICHE POUR TOUT LE MONDE depuis le 26/08/2026, plus
       * seulement pour les inscriptions sans adresse. L'Alanya ID trônait
       * auparavant en tête de l'écran de profil, avant même que le compte
       * existe : on le lisait alors qu'il restait trois champs à remplir, donc
       * on ne le lisait pas. Il est désormais montré ICI et nulle part ailleurs
       * dans le parcours — au seul moment où il n'y a plus rien à faire que le
       * noter (demande du user).
       *
       * ⚠️ AVANT `completeSetup`, et c'est délibéré. Ouvrir la session d'abord
       * ferait basculer la racine de l'application sur l'accueil, et cet écran
       * apparaîtrait par-dessus un écran d'accueil en train de se construire.
       * Ici, le parcours reste une suite d'écrans, dans l'ordre.
       *
       * ⚠️ L'attente ne se termine QUE par le bouton « Continuer » de l'écran :
       * il neutralise le geste « retour » du système (`PopScope`), sans quoi on
       * pourrait renvoyer l'écran d'un balayage.
       *
       * Le compte est déjà créé et son mot de passe posé à ce stade : quelqu'un
       * qui fermerait l'application ici ne perd rien — il se connecte avec son
       * numéro et retrouve le code dans `Réglages ▸ Sécurité`.
       */
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ecran) => FinInscriptionScreen(
            publicNumber: widget.publicNumber,
            idRecuperation: widget.idRecuperation,
            // `ecran` et non le `context` de l'écran de profil : c'est la
            // route qu'on vient de pousser qu'il faut refermer.
            onContinuer: () => Navigator.of(ecran).pop(),
          ),
        ),
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

  /// Une indication qui coiffe un champ.
  ///
  /// Même couleur et même taille que celle du numéro, pour qu'elles se lisent
  /// comme une seule famille — seul l'alignement les distingue.
  Widget _indication(BuildContext context, String texte) => Text(
        texte,
        style: TextStyle(
          color: mutedOf(context, Colors.black54),
          fontSize: 13.5,
          height: 1.4,
        ),
      );

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

                // --- Pays et téléphone ---
                //
                // 🔴 LE PAYS VIENT AVANT LE NUMÉRO, ET DANS LE MÊME BLOC.
                // Le menu Pays était en DERNIER, après le numéro, alors que
                // c'est lui qui donne l'indicatif : on tapait son numéro sans
                // savoir devant quoi il allait se coller, et changer de pays
                // ensuite réécrivait la saisie.
                //
                // ⚠️ MÊME COMPOSANT QUE DANS LES RÉGLAGES. Les deux endroits
                // qui demandent un numéro avaient chacun leur formulaire —
                // c'est ainsi qu'un numéro finit stocké sous deux formes dans
                // une colonne UNIQUE.
                Text(
                  tr(context, 'phone_number_sub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: mutedOf(context, Colors.black54),
                      fontSize: 14,
                      height: 1.4),
                ),
                const SizedBox(height: 20),
                SaisiePaysNumero(
                  pays: _pays,
                  idPays: _selectedPaysId,
                  controller: _mobileCtrl,
                  onPays: (id) => setState(() => _selectedPaysId = id),
                  actif: !_loading,
                ),
                // Tant que la table de référence n'arrive pas, on le dit :
                // un sélecteur muet ressemble à une panne.
                if (_paysErreur || _pays.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr(context,
                        _paysErreur ? 'server_unreachable' : 'loading'),
                    style: TextStyle(
                        fontSize: 12,
                        color: mutedOf(context, Colors.black54)),
                  ),
                ],
                const SizedBox(height: 24),

                // --- Mot de passe ---
                //
                // L'indication est ALIGNÉE À GAUCHE, là où celle du numéro est
                // centrée : celle-ci coiffe un champ, celle-là coiffe un bloc
                // de deux. La différence d'alignement dit donc la portée, au
                // lieu de la laisser deviner.
                //
                // ⚠️ Elle dit la règle AVANT la saisie. Le minimum de huit
                // caractères n'apparaissait qu'en rouge, une fois le formulaire
                // envoyé — on découvrait la contrainte en la violant.
                _indication(context, tr(context, 'password_setup_hint')),
                const SizedBox(height: 8),
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
                _indication(context, tr(context, 'password_confirm_hint')),
                const SizedBox(height: 8),
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
