import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_snackbar.dart';
import '../../core/device_registry.dart';
import '../../core/realtime_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/e2ee/e2ee_contacts_recuperation.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../../services/e2ee/e2ee_sauvegarde.dart';
import '../account/account_repository.dart';

/// LA VEILLE DE LA SAUVEGARDE, SUR CHAQUE APPAREIL CONNECTÉ (27/11/2026).
///
/// 🔴 JUMELLE DE `STAGE-WEB/src/components/veille-sauvegarde.tsx`.
///
/// Trois choses, au démarrage, au retour au premier plan et à chaque signal
/// d'un autre appareil du compte :
///
///  1. CET appareil attendait la clé : si elle est arrivée, on la range et
///     l'on restaure. Après un redémarrage, la clé éphémère est perdue : si la
///     sauvegarde est toujours fermée ici, on redemande (au plus deux fois par
///     jour) — sans mot de passe, donc avec l'accord d'un autre appareil ;
///  2. un AUTRE appareil attend la clé : si elle est ici, on la lui transmet —
///     d'elle-même quand le serveur le permet, sinon après « Autoriser » ;
///  3. la serrure « mot de passe » ne suit plus le mot de passe (couche B) :
///     un bandeau propose de la refaire, en confirmant le mot de passe.
///
/// ⚠️ RIEN NE BLOQUE : « Plus tard » ferme tout jusqu'au prochain démarrage.
class VeilleSauvegarde {
  VeilleSauvegarde._();
  static final instance = VeilleSauvegarde._();

  BuildContext? _contexte;
  StreamSubscription<Map<String, dynamic>>? _signaux;
  AppLifecycleListener? _cycle;
  bool _enCours = false;
  // Un signal arrivé pendant une vérification n'est pas perdu : on refait un tour.
  bool _relancer = false;
  Timer? _releve;
  bool _premierPlan = true;
  DateTime _dernier = DateTime.fromMillisecondsSinceEpoch(0);
  final _ecartees = <String>{};
  bool _bandeauEcarte = false;
  bool _bandeauAffiche = false;

  static const _pause = Duration(minutes: 1);
  /// Les demandes des autres appareils se relisent aussi d'elles-mêmes, au
  /// premier plan : le signal temps réel peut se perdre. Une requête légère.
  static const _relectureDemandes = Duration(seconds: 30);
  static const _entreDeuxRedemandes = Duration(hours: 12);

  void brancher(BuildContext context) {
    _contexte = context;
    _signaux?.cancel();
    _signaux = context.read<RealtimeClient>().events.listen((e) {
      if (e['type'] == 'e2ee_sauvegarde' || e['type'] == 'e2ee_recuperation') {
        unawaited(verifier(force: true));
      }
    });
    _cycle?.dispose();
    _cycle = AppLifecycleListener(
      onResume: () {
        _premierPlan = true;
        unawaited(verifier());
      },
      onPause: () => _premierPlan = false,
    );
    _releve?.cancel();
    _releve = Timer.periodic(_relectureDemandes, (_) {
      if (_premierPlan) unawaited(_relireDemandes());
    });
    unawaited(verifier(force: true));
  }

  /// Seulement les demandes des autres appareils : le tour léger.
  Future<void> _relireDemandes() async {
    final ctx = _contexte;
    if (ctx == null || !ctx.mounted || _enCours) return;
    final pile = ctx.e2ee;
    if (pile == null || !pile.sauvegarde.estOuverte) return;
    final rt = ctx.read<RealtimeClient>();
    _enCours = true;
    try {
      final s = pile.sauvegarde;
      for (final d in await s.demandesCleOuvertes(await DeviceRegistry.instance.deviceId())) {
        if (d.auto) {
          if (await s.servirDemandeCle(d, pile.compteId)) {
            rt.sendSignalSauvegarde('demande_cle_traitee', id: d.id);
          }
          continue;
        }
        if (_ecartees.contains(d.id) || !ctx.mounted) continue;
        await _demander(ctx, d, pile.compteId);
        break;
      }
    } finally {
      _enCours = false;
    }
  }

  void debrancher() {
    _releve?.cancel();
    _releve = null;
    _signaux?.cancel();
    _signaux = null;
    _cycle?.dispose();
    _cycle = null;
    _contexte = null;
  }

  Future<void> verifier({bool force = false}) async {
    final ctx = _contexte;
    if (ctx == null || !ctx.mounted) return;
    if (_enCours) {
      if (force) _relancer = true;
      return;
    }
    if (!force && DateTime.now().difference(_dernier) < _pause) return;
    final pile = ctx.e2ee;
    if (pile == null) return;
    final rt = ctx.read<RealtimeClient>();
    _enCours = true;
    _dernier = DateTime.now();
    try {
      final s = pile.sauvegarde;
      final compte = pile.compteId;
      final appareil = await DeviceRegistry.instance.deviceId();

      // ① Ma demande.
      if (s.demandeEnAttente) {
        if (await s.relireDemandeCle(pile.coffre, compte) == IssueDemande.recue) {
          if (ctx.mounted) showAppSnackBar(tr(ctx, 'arch_cle_recue'));
          try {
            await s.restaurer();
          } catch (_) {}
          unawaited(pile.fil.groupe.restaurerTous());
        }
      } else if (!s.estOuverte && await _peutRedemander(compte) && await s.aUneArchive()) {
        final id = await s.demanderCleAuxAppareils(
          appareil: appareil,
          libelle: DeviceRegistry.instance.libelle,
        );
        if (id != null) {
          rt.sendSignalSauvegarde('demande_cle', id: id);
          await _noterRedemande(compte);
        }
      }

      // ①bis Mon aide demandée à mes contacts : arrivée ?
      final contacts = ContactsRecuperation(pile);
      if (contacts.aideEnAttente && await contacts.relire() == IssueAide.recue) {
        if (ctx.mounted) showAppSnackBar(tr(ctx, 'arch_cle_recue'));
        try {
          await s.restaurer();
        } catch (_) {}
        unawaited(pile.fil.groupe.restaurerTous());
      }

      // ②bis Ce que d'autres me demandent, en tant que contact de récupération.
      if (ctx.mounted) await _recuperation(ctx, contacts);

      if (!s.estOuverte) return;

      // ② Les demandes des autres appareils.
      for (final d in await s.demandesCleOuvertes(appareil)) {
        if (d.auto) {
          if (await s.servirDemandeCle(d, compte)) {
            rt.sendSignalSauvegarde('demande_cle_traitee', id: d.id);
          }
          continue;
        }
        if (_ecartees.contains(d.id) || !ctx.mounted) continue;
        await _demander(ctx, d, compte);
        break;
      }

      // ③ La serrure périmée.
      if (!_bandeauEcarte && !_bandeauAffiche && ctx.mounted &&
          await s.serrureMotDePassePerimee(compte) && ctx.mounted) {
        _montrerBandeau(ctx);
      }
    } finally {
      _enCours = false;
      if (_relancer) {
        _relancer = false;
        unawaited(verifier(force: true));
      }
    }
  }

  /// Invitations et demandes d'aide qui m'attendent, en tant que contact.
  Future<void> _recuperation(BuildContext ctx, ContactsRecuperation contacts) async {
    final a = await contacts.aTraiter();
    final inv = a.invitations.where((i) => !_ecartees.contains(i.id)).firstOrNull;
    if (inv != null && ctx.mounted) {
      final nom = inv.nom ?? '—';
      final choix = await showDialog<String>(
        context: ctx,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.groups_outlined),
          title: Text(tr(c, 'recup_titre')),
          content: Text(tr(c, 'recup_invitation_texte').replaceAll('{nom}', nom)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'plus_tard'), child: Text(tr(c, 'arch_plus_tard'))),
            TextButton(onPressed: () => Navigator.pop(c, 'non'), child: Text(tr(c, 'recup_refuser'))),
            FilledButton(onPressed: () => Navigator.pop(c, 'oui'), child: Text(tr(c, 'recup_accepter'))),
          ],
        ),
      );
      if (choix == 'oui' || choix == 'non') {
        await contacts.repondreInvitation(inv.id, choix == 'oui');
      } else {
        _ecartees.add(inv.id);
      }
      return;
    }
    final d = a.demandes.where((x) => !_ecartees.contains(x.id)).firstOrNull;
    if (d == null || !ctx.mounted) return;
    final nom = d.nom ?? '—';
    final choix = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.support_outlined),
        title: Text(tr(c, 'recup_demande_titre').replaceAll('{nom}', nom)),
        content: Text(tr(c, 'recup_demande_texte').replaceAll('{nom}', nom)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'plus_tard'), child: Text(tr(c, 'arch_plus_tard'))),
          TextButton(
            onPressed: () => Navigator.pop(c, 'non'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
            child: Text(tr(c, 'recup_je_refuse')),
          ),
          FilledButton(onPressed: () => Navigator.pop(c, 'oui'), child: Text(tr(c, 'recup_aider'))),
        ],
      ),
    );
    if (choix == 'oui') {
      final ok = await contacts.aider(d);
      if (ctx.mounted) showAppSnackBar(tr(ctx, ok ? 'recup_aide_envoyee' : 'recup_erreur'));
    } else if (choix == 'non') {
      await contacts.refuserAide(d);
    } else {
      _ecartees.add(d.id);
    }
  }

  static String _cleRedemande(String compte) => 'demande_cle_derniere_$compte';

  Future<bool> _peutRedemander(String compte) async {
    final quand = (await SharedPreferences.getInstance()).getInt(_cleRedemande(compte));
    return quand == null ||
        DateTime.now().millisecondsSinceEpoch - quand > _entreDeuxRedemandes.inMilliseconds;
  }

  Future<void> _noterRedemande(String compte) async {
    await (await SharedPreferences.getInstance())
        .setInt(_cleRedemande(compte), DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _demander(BuildContext ctx, DemandeCle d, String compte) async {
    final pile = ctx.e2ee;
    if (pile == null) return;
    final rt = ctx.read<RealtimeClient>();
    final choix = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.devices_outlined),
        title: Text(tr(c, 'arch_demande_titre')),
        content: Text(tr(c, 'arch_demande_texte').replaceAll(
          '{appareil}',
          d.libelle.isEmpty ? tr(c, 'arch_demande_inconnu') : d.libelle,
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'plus_tard'),
            child: Text(tr(c, 'arch_plus_tard')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'refuser'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
            child: Text(tr(c, 'arch_demande_refuser')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'autoriser'),
            child: Text(tr(c, 'arch_demande_autoriser')),
          ),
        ],
      ),
    );
    if (choix == 'autoriser') {
      if (await pile.sauvegarde.servirDemandeCle(d, compte)) {
        rt.sendSignalSauvegarde('demande_cle_traitee', id: d.id);
      }
    } else if (choix == 'refuser') {
      final appareil = await pile.sauvegarde.refuserDemandeCle(d);
      rt.sendSignalSauvegarde('demande_cle_traitee', id: d.id);
      if (appareil != null) rt.sendSessionRevoked(appareil);
      if (ctx.mounted) showAppSnackBar(tr(ctx, 'arch_demande_refusee_ok'));
    } else {
      _ecartees.add(d.id);
    }
  }

  void _montrerBandeau(BuildContext ctx) {
    final messager = ScaffoldMessenger.maybeOf(ctx);
    if (messager == null) return;
    _bandeauAffiche = true;
    void fermer() {
      messager.hideCurrentMaterialBanner();
      _bandeauAffiche = false;
    }

    messager.showMaterialBanner(MaterialBanner(
      leading: const Icon(Icons.key_outlined),
      content: Text(tr(ctx, 'arch_bandeau_perimee')),
      actions: [
        TextButton(
          onPressed: () {
            _bandeauEcarte = true;
            fermer();
          },
          child: Text(tr(ctx, 'arch_plus_tard')),
        ),
        TextButton(
          onPressed: () async {
            fermer();
            if (ctx.mounted && !await _confirmerMotDePasse(ctx)) _bandeauEcarte = true;
          },
          child: Text(tr(ctx, 'arch_bandeau_confirmer')),
        ),
      ],
    ));
  }

  /// Demande le mot de passe actuel, le fait vérifier, puis refait la serrure.
  Future<bool> _confirmerMotDePasse(BuildContext ctx) async {
    final pile = ctx.e2ee;
    if (pile == null) return false;
    final depot = ctx.read<AccountRepository>();
    final saisie = TextEditingController();
    final mdp = await showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'arch_relier_titre')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(c, 'arch_relier_texte')),
          const SizedBox(height: 12),
          TextField(
            controller: saisie,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: tr(c, 'current_password')),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'arch_plus_tard'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, saisie.text),
            child: Text(tr(c, 'arch_bandeau_confirmer')),
          ),
        ],
      ),
    );
    saisie.dispose();
    if (mdp == null || mdp.isEmpty) return false;
    try {
      await depot.verifierMotDePasse(mdp);
    } catch (_) {
      if (ctx.mounted) showAppSnackBar(tr(ctx, 'arch_mdp_incorrect'));
      return false;
    }
    final ok = await pile.sauvegarde.relierAuMotDePasse(mdp, compte: pile.compteId);
    if (ctx.mounted) showAppSnackBar(tr(ctx, ok ? 'arch_relier_ok' : 'arch_suivi_echoue'));
    return ok;
  }
}
