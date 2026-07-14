import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/call_cache.dart';
import '../../core/contact_cache.dart';
import '../../core/conversation_cache.dart';
import '../../core/message_cache.dart';
import '../../core/push_service.dart';
import '../../core/token_storage.dart';
import '../../models/auth_user.dart';
import 'auth_repository.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

/// État global d'authentification (exposé via Provider).
class AuthController extends ChangeNotifier {
  AuthController(this._repo, this._storage);

  final AuthRepository _repo;
  final TokenStorage _storage;

  AuthStatus status = AuthStatus.unknown;
  AuthUser? user;

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
          user = AuthUser.fromJson(jsonDecode(cachedUser) as Map<String, dynamic>);
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
          await _storage.saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken);
          final u = await _repo.me(tokens.accessToken);
          await _saveUserCache(u);
          _set(AuthStatus.authenticated, u);
          return;
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

  Future<void> completeLogin(AuthSession session) => _persist(session);

  /// Met à jour localement le profil après une modification réussie côté API.
  void applyProfile({String? pseudo, String? avatarUrl, String? statusMsg}) {
    final current = user;
    if (current == null) return;
    user = current.copyWith(pseudo: pseudo, avatarUrl: avatarUrl, statusMsg: statusMsg);
    _saveUserCache(user!); // fire-and-forget
    notifyListeners();
  }

  Future<void> logout() async {
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
    await _saveUserCache(session.user);
    user = session.user;
    _set(AuthStatus.authenticated, session.user);
    // Ré-enregistre le token FCM : maintenant qu'on est authentifié,
    // le backend peut associer le token à l'utilisateur.
    PushService.instance.registerTokenIfAuthenticated();
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
    }
  }
}
