import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../features/auth/auth_controller.dart';
import '../features/calls/calls_repository.dart';
import '../features/collegues/collegues_repository.dart';
import '../features/entreprises/entreprises_repository.dart';
import '../features/meetings/meetings_repository.dart';
import '../features/status/status_repository.dart';
import 'call_cache.dart';
import 'connectivity_service.dart';
import 'conversation_cache.dart';
import 'images_badges.dart';

/// PRÉCHARGEMENT ANTICIPÉ des écrans du menu (préchauffage du cache).
///
/// 🔴 DEMANDE DU USER (18/10/2026) : à l'ouverture de la session, l'application
/// télécharge en arrière-plan les données des écrans du menu, avec leurs
/// filtres par défaut. Chaque onglet s'ouvre ensuite AUSSITÔT avec cette
/// copie, puis se met à jour (voir `CacheEcrans`, `CallCache`).
///
/// ⚠️ IL S'ARRÊTE HORS LIGNE, et reprend où il en était au retour du réseau :
/// chaque essai sur un téléphone sans réseau attendrait son délai d'expiration
/// pour rien, et occuperait la connexion qui revient.
///
/// ⚠️ LES DISCUSSIONS N'Y SONT PAS : c'est l'onglet affiché à l'ouverture, il
/// charge déjà lui-même. Le préchargement passe APRÈS lui, d'où le délai de
/// départ — il ne doit pas lui disputer la connexion.
///
/// ⚠️ UN ÉCHEC EST IGNORÉ : l'écran refera la requête à son ouverture.
class PrechargementEcrans {
  PrechargementEcrans._(this._etapes, this._connexion);

  static PrechargementEcrans? _enCours;

  final List<(String, Future<void> Function())> _etapes;
  final ConnectivityService _connexion;
  int _suivante = 0;
  bool _fini = false;
  bool _actif = false;

  /// Lance le préchargement de la session ouverte. Un second appel pendant
  /// qu'il tourne ne fait rien.
  static void lancer(BuildContext context) {
    if (_enCours != null && !_enCours!._fini) return;
    // Le type de compte est relu À L'ÉTAPE : juste après une connexion, le
    // profil complet n'est pas encore arrivé et il vaut 0 pour tout le monde.
    final auth = context.read<AuthController>();
    final statuts = context.read<StatusRepository>();
    final appels = context.read<CallsRepository>();
    final reunions = context.read<MeetingsRepository>();
    final collegues = context.read<ColleguesRepository>();
    final entreprises = context.read<EntreprisesRepository>();

    final p = PrechargementEcrans._([
      ('statuts', () => statuts.feed()),
      ('appels', () async => CallCache.putAll(await appels.history())),
      ('reunions', () => reunions.fetchMeetings()),
      // Mêmes conditions que les onglets de `HomeScreen`.
      ('annuaire', () async {
        if (auth.user?.typeCompte == 2) await collegues.services();
      }),
      ('entreprises', () async {
        if (auth.user?.typeCompte == 0) await entreprises.types();
      }),
      ('badges', () async {
        final convs = await ConversationCache.getAll();
        await ImagesBadges.prechauffer(
            [for (final c in convs) if (c.badge != null) c.badge!.image]);
      }),
    ], context.read<ConnectivityService>());
    _enCours = p;
    p._connexion.addListener(p._surConnexion);
    unawaited(Future.delayed(const Duration(seconds: 2), p._derouler));
  }

  /// Fin de session : le préchargement suivant repartira de zéro.
  static void arreter() {
    final p = _enCours;
    _enCours = null;
    p?._terminer();
  }

  void _surConnexion() {
    if (!_connexion.isOffline && !_fini && !_actif) unawaited(_derouler());
  }

  Future<void> _derouler() async {
    if (_actif || _fini || _enCours != this) return;
    _actif = true;
    try {
      while (_suivante < _etapes.length) {
        if (_connexion.isOffline || _enCours != this) return;
        final (nom, etape) = _etapes[_suivante];
        try {
          await etape();
        } catch (e) {
          debugPrint('[Préchargement] $nom : $e');
          // Coupé en route : cette étape sera rejouée au retour du réseau.
          if (_connexion.isOffline) return;
        }
        _suivante++;
      }
      _terminer();
    } finally {
      _actif = false;
    }
  }

  void _terminer() {
    if (_fini) return;
    _fini = true;
    _connexion.removeListener(_surConnexion);
  }
}
