import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/call_cache.dart';
import '../../core/call_ui_native.dart';
import '../../core/contact_cache.dart';
import '../../core/conversation_cache.dart';
import '../../core/message_cache.dart';
import '../../core/device_registry.dart';
import '../../core/geo_service.dart';
import '../../core/push_service.dart';
import '../../core/realtime_client.dart';
import '../../core/token_storage.dart';
import '../../models/auth_user.dart';
import 'auth_repository.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

/// État global d'authentification (exposé via Provider).
class AuthController extends ChangeNotifier {
  AuthController(this._repo, this._storage, {RealtimeClient? realtime})
      : _realtime = realtime;

  final AuthRepository _repo;
  final TokenStorage _storage;
  final RealtimeClient? _realtime;

  AuthStatus status = AuthStatus.unknown;
  AuthUser? user;

  /// Pourquoi la session s'est fermée, quand ce n'est pas l'utilisateur qui
  /// l'a voulu. Affiché une seule fois sur l'écran de connexion, puis effacé
  /// par [messageDeconnexionLu].
  ///
  /// Nul dans le cas ordinaire : une déconnexion volontaire n'a rien à
  /// expliquer.
  String? messageDeconnexion;

  /// À appeler dès que le message a été montré : il ne doit pas réapparaître à
  /// la prochaine ouverture de l'écran de connexion.
  void messageDeconnexionLu() {
    if (messageDeconnexion == null) return;
    messageDeconnexion = null;
    notifyListeners();
  }

  /// Raison envoyée avec `session_revoked` quand c'est une nouvelle connexion
  /// qui ferme les autres, et non un ménage volontaire.
  static const raisonEviction = "eviction";

  StreamSubscription<Map<String, dynamic>>? _revocationSub;

  /// Déconnexion à distance : une autre session du compte a révoqué un
  /// appareil. Chaque client compare l'identifiant reçu au sien ; seul celui
  /// qui est visé s'efface.
  ///
  /// La révocation en base reste la garantie de fond — cet événement évite
  /// simplement d'attendre l'expiration du jeton d'accès (15 minutes).
  void _ecouterRevocation() {
    final rt = _realtime;
    if (rt == null || _revocationSub != null) return;
    _revocationSub = rt.events.listen((e) async {
      if (e["type"] != "session_revoked") return;
      final vise = e["deviceId"] as String?;
      if (vise == null) return;
      if (vise != await DeviceRegistry.instance.deviceId()) return;
      // Deux causes passent par le même événement, et elles n'appellent pas le
      // même message : une connexion ailleurs, ou un ménage que l'utilisateur a
      // fait lui-même depuis « Appareils connectés ». Sans la raison, on
      // annoncerait une intrusion à quelqu'un qui vient de ranger ses appareils.
      if (e["raison"] == raisonEviction) {
        messageDeconnexion = "Votre compte a été ouvert sur un autre appareil.";
      }
      await logout();
    });
  }

  @override
  void dispose() {
    _revocationSub?.cancel();
    super.dispose();
  }

  /// Au démarrage : tente de restaurer une session depuis les tokens stockés.
  /// - Si un access_token est présent, on tente /api/me
  /// - Si 401 (token expiré), on tente un refresh avec le refresh_token
  /// - Si le refresh réussit, on rejoue /api/me
  /// - En cas d'échec total, on efface et on passe en unauthenticated
  /// - On restaure aussi le profil utilisateur en cache pour un affichage instantané
  Future<void> bootstrap() async {
    try {
      // 1. Restaure le profil en cache pour un démarrage instantané (optionnel)
      final cachedUser = await _storage.userJson;
      if (cachedUser != null) {
        try {
          user =
              AuthUser.fromJson(jsonDecode(cachedUser) as Map<String, dynamic>);
          // On reste en unknown le temps de valider le token, mais l'UI peut déjà afficher le pseudo
          notifyListeners();
        } catch (_) {}
      }

      final access = await _storage.accessToken;
      final refresh = await _storage.refreshToken;

      if (access == null && refresh == null) {
        _set(AuthStatus.unauthenticated, null);
        return;
      }

      // 2. Essaye avec l'access token courant
      if (access != null) {
        try {
          final u = await _repo.me(access);
          await _saveUserCache(u);
          _set(AuthStatus.authenticated, u);
          return;
        } on ApiException catch (e) {
          // Si ce n'est pas une 401, c'est une vraie erreur réseau – on garde la session en cache si possible
          if (e.statusCode != 401 || refresh == null) {
            // Si on a un user en cache, reste authentifié en mode offline
            if (user != null) {
              _set(AuthStatus.authenticated, user);
              return;
            }
            rethrow;
          }
          // 401 → on va tenter le refresh ci-dessous
        }
      }

      // 3. Access expiré ou manquant → tente refresh
      if (refresh != null) {
        try {
          final tokens = await _repo.refresh(refresh);
          await _storage.saveTokens(
              access: tokens.accessToken, refresh: tokens.refreshToken);
          final u = await _repo.me(tokens.accessToken);
          await _saveUserCache(u);
          _set(AuthStatus.authenticated, u);
          return;
        } on ApiException catch (e) {
          // ⚠️ LE SEUL CHEMIN qui couvre l'appareil ÉTEINT au moment de
          // l'éviction : il n'a pas reçu l'événement temps réel, et ne
          // l'apprend qu'en tentant de se rafraîchir à son réveil. Sans ce cas,
          // il retomberait sur l'écran de connexion sans la moindre explication.
          if (e.code == "SESSION_EVINCEE") {
            messageDeconnexion =
                "Votre compte a été ouvert sur un autre appareil.";
          }
        } catch (_) {
          // refresh échoué → on nettoie
        }
      }

      // 4. Échec total
      await _storage.clear();
      _set(AuthStatus.unauthenticated, null);
    } catch (_) {
      // Erreur de lecture du secure storage, ou réseau : si on a un cache user, reste authentifié
      if (user != null) {
        _set(AuthStatus.authenticated, user);
        return;
      }
      await _storage.clear();
      _set(AuthStatus.unauthenticated, null);
    }
  }

  Future<void> completeSetup(AuthSession session) => _persist(session);

  Future<void> completeLogin(AuthSession session) async {
    await _persist(session);
    // Un message resté d'une éviction précédente n'a plus lieu d'être : on
    // vient de se reconnecter, l'incident est clos.
    messageDeconnexion = null;
    _annonceLesEvictions(session.sessionsFermees);
  }

  /// Prévient TOUT DE SUITE les appareils que cette connexion vient de fermer.
  ///
  /// Le serveur les a déjà coupés en base — c'est la garantie de fond. Mais
  /// l'API et le serveur temps réel sont deux process sans canal entre eux :
  /// sans cette annonce, les appareils sortants resteraient utilisables jusqu'à
  /// l'expiration de leur jeton d'accès, soit un quart d'heure.
  ///
  /// La trame part alors que le WebSocket vient tout juste d'être ouvert par
  /// `_persist` : c'est pour ce moment précis que `session_revoked` a rejoint
  /// les types mis en attente jusqu'à la connexion.
  void _annonceLesEvictions(List<String> appareils) {
    final rt = _realtime;
    if (rt == null || appareils.isEmpty) return;
    for (final deviceId in appareils) {
      rt.sendSessionRevoked(deviceId, raison: raisonEviction);
    }
  }

  /// Met à jour localement le profil après une modification réussie côté API.
  void applyProfile({String? pseudo, String? avatarUrl, String? statusMsg}) {
    final current = user;
    if (current == null) return;
    user = current.copyWith(
        pseudo: pseudo, avatarUrl: avatarUrl, statusMsg: statusMsg);
    _saveUserCache(user!); // fire-and-forget
    notifyListeners();
  }

  Future<void> logout() async {
    // Ferme tout écran d'appel natif encore affiché.
    //
    // CallKit vit HORS de l'application : ses écrans survivent à la
    // déconnexion, et même à la fermeture. Sans ce nettoyage, un appel du
    // compte qu'on vient de quitter continuait de sonner sur le téléphone
    // après connexion avec un AUTRE compte — l'écran natif ne sait pas qu'on a
    // changé d'utilisateur.
    //
    // En premier, avant même le jeton push : si la suite échoue, l'écran
    // fantôme aura au moins disparu.
    await CallUiNative.toutMasquer();

    // Arrête le relevé de position. Sans cela, le téléphone continuerait de
    // rapporter la position d'un compte qui n'est plus connecté — et les envois
    // échoueraient en boucle, faute de jeton.
    GeoService.instance.arreter();

    // Désenregistre le token FCM avant de nettoyer les tokens locaux
    await PushService.instance.unregister();
    final refresh = await _storage.refreshToken;
    if (refresh != null) {
      try {
        await _repo.logout(refresh);
      } catch (_) {
        // on ignore : on déconnecte localement de toute façon
      }
    }
    await _storage.clear();
    await MessageCache.clear();
    // Déconnecte le WebSocket avant de nettoyer la session.
    _realtime?.disconnect();
    // Purge des caches offline : la session change, un autre user pourrait
    // se connecter sur ce téléphone.
    await ConversationCache.clear();
    await CallCache.clear();
    await ContactCache.clear();
    _set(AuthStatus.unauthenticated, null);
  }

  Future<void> _persist(AuthSession session) async {
    await _storage.saveTokens(
      access: session.accessToken,
      refresh: session.refreshToken,
    );

    /*
     * 🔴 LE PROFIL EST RELU SUR `/api/me`, ET NON PRIS DANS LA RÉPONSE DE
     * CONNEXION — qui est INCOMPLÈTE.
     *
     * `POST /api/auth/login` ne rend que six champs : id, email, publicNumber,
     * pseudo, avatarUrl, isOnline. Tout le reste manque, et `AuthUser.fromJson`
     * le remplace donc par ses valeurs par défaut : `typeCompte` tombe à 0,
     * `nom`, `idPays`, `mobile`, `statusMsg` à null, `suiviPosition` à faux.
     *
     * Constaté le 25/08/2026 : l'onglet Collègues, conditionné à
     * `typeCompte == 2`, restait invisible pour l'agent `chiwen` — qui EST de
     * type 2 en base. Il n'apparaissait qu'au redémarrage suivant, quand le
     * démarrage appelle `/api/me` et corrige le profil. Le même piège attendait
     * le suivi de position et tout écran qui lirait un de ces champs.
     *
     * Relire ici règle la famille entière plutôt qu'un champ : la session juste
     * ouverte porte le MÊME profil que celui d'un démarrage.
     *
     * ⚠️ L'ÉCHEC N'EST PAS BLOQUANT. Sans réseau à cet instant précis, on
     * retombe sur le profil partiel de la connexion : mieux vaut entrer avec un
     * profil incomplet — que le prochain démarrage complétera — que de refuser
     * une connexion pourtant accordée par le serveur.
     */
    var profil = session.user;
    try {
      profil = await _repo.me(session.accessToken);
    } catch (_) {}

    await _saveUserCache(profil);
    user = profil;
    _set(AuthStatus.authenticated, profil);
    // Ré-enregistre le token FCM : maintenant qu'on est authentifié,
    // le backend peut associer le token à l'utilisateur.
    PushService.instance.registerTokenIfAuthenticated();
    // Inscrit l'appareil au registre du compte (écran « Appareils connectés »).
    DeviceRegistry.instance.registerIfAuthenticated();
    // Reconnecte le WebSocket avec le nouveau token (empêche le bug où
    // le WS reste ouvert avec le token du précédent utilisateur).
    _realtime?.connect();
  }

  Future<void> _saveUserCache(AuthUser u) async {
    try {
      final json = jsonEncode({
        'id': u.id,
        'email': u.email,
        'publicNumber': u.publicNumber,
        'pseudo': u.pseudo,
        'avatarUrl': u.avatarUrl,
        'statusMsg': u.statusMsg,
      });
      await _storage.saveUserJson(json);
    } catch (_) {}
  }

  void _set(AuthStatus s, AuthUser? u) {
    final wasAuth = status == AuthStatus.authenticated;
    status = s;
    user = u;
    notifyListeners();
    // Déclenche l'enregistrement du token FCM dès qu'on devient authentifié.
    // Corrige le bug de timing : le token n'était jamais enregistré car
    // tryInitialize() s'exécutait avant l'authentification.
    if (s == AuthStatus.authenticated && !wasAuth) {
      PushService.instance.registerTokenIfAuthenticated();
      // Couvre aussi le redémarrage à froid : la session est restaurée sans
      // repasser par _persist, l'appareil doit quand même se signaler.
      DeviceRegistry.instance.registerIfAuthenticated();
      _realtime?.connect();
      _ecouterRevocation();
    } else if (s == AuthStatus.unauthenticated && wasAuth) {
      _revocationSub?.cancel();
      _revocationSub = null;
      _realtime?.disconnect();
    }
  }
}
