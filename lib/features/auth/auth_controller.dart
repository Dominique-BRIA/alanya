import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/call_cache.dart';
import '../../core/call_ui_native.dart';
import '../../core/contact_cache.dart';
import '../../core/verrou_rafraichissement.dart';
import '../../core/memoire_langues.dart';
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

/// Les seuls verdicts qui ferment une session.
///
/// 🔴 UNE LISTE EXPLICITE, ET NON « UN 4xx QUELCONQUE ». C'est le changement de
/// fond : la règle précédente détruisait la session sur n'importe quelle
/// réponse 4xx du rafraîchissement, `BAD_REFRESH` compris. Or `BAD_REFRESH`
/// tombait sur le cas le plus banal qui soit — un jeton déjà tourné, donc un
/// simple réessai. L'utilisateur se retrouvait devant l'écran de connexion
/// alors que RIEN n'avait expiré.
///
/// Chacun de ces trois codes est une décision que le serveur a prise SUR CETTE
/// SESSION, et qu'il nomme :
const codesSessionFermee = {
  /// Le compte a été ouvert sur un autre appareil de la même famille.
  "SESSION_EVINCEE",

  /// Un jeton copié a circulé : la chaîne de cet appareil a été coupée.
  "JETON_REJOUE",

  /// L'utilisateur a fermé cette session depuis « Appareils connectés ».
  "SESSION_REVOQUEE",

  /// Jeton inconnu du serveur, ou validité de sept jours écoulée.
  ///
  /// ⚠️ SANS CE CODE, UNE SESSION VRAIMENT PÉRIMÉE NE SE FERMERAIT JAMAIS :
  /// l'application réessaierait indéfiniment avec un jeton mort. C'est le
  /// revers de la nouvelle règle — ne plus se fier au statut HTTP oblige le
  /// serveur à nommer AUSSI les fins normales, pas seulement les incidents.
  "SESSION_EXPIREE",
};

/// Ce rafraîchissement raté doit-il DÉTRUIRE la session ?
///
/// 🔴 LA RÈGLE QUI A RÉGRESSÉ DEUX FOIS, ET LA RAISON DE CETTE FONCTION.
///
/// Premier temps (26/08/2026) : les clients confondaient « le serveur a REFUSÉ
/// mon jeton » avec « je n'ai pas pu joindre le serveur ». Une coupure réseau,
/// un 502 pendant un redéploiement, un lancement hors ligne : la session était
/// perdue. Corrigé en n'agissant que sur un 4xx.
///
/// Second temps, corrigé ici : « un 4xx » était encore beaucoup trop large.
/// La rotation révoque l'ancien jeton à CHAQUE rafraîchissement ; tout réessai
/// — réponse perdue, application tuée avant l'écriture du nouveau jeton, deux
/// chemins qui se rafraîchissent ensemble — recevait 401 `BAD_REFRESH` et
/// déclenchait une déconnexion. C'est la cause des « déconnexions alors que le
/// jeton n'est pas expiré ».
///
/// ⚠️ EN CAS DE DOUTE, ON GARDE — la règle n'a pas changé, seule la liste des
/// certitudes s'est resserrée. Une session gardée à tort se corrige au
/// rafraîchissement suivant ; une session détruite à tort oblige à retaper son
/// mot de passe et fait perdre le cache hors ligne.
///
/// ⚠️ LE SERVEUR DÉCIDE, PAS LE CODE HTTP. Un 401 sans code nommé n'est plus
/// qu'un échec de plus : on réessaiera.
bool sessionMorteApresEchec(Object erreur) {
  if (erreur is! ApiException) return false;
  return codesSessionFermee.contains(erreur.code);
}

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
          /*
           * ⚠️ PAR LE VERROU PARTAGÉ, et non plus en direct.
           *
           * 🔴 C'ÉTAIT LA COURSE LA PLUS FRÉQUENTE. Ce chemin s'exécute au
           * démarrage — exactement quand tout part en même temps : restauration
           * de session, notifications en attente, premiers écrans qui
           * interrogent l'API. `AuthedApi` avait bien un verrou ; celui-ci
           * l'ignorait. Les deux se rafraîchissaient donc avec le MÊME jeton,
           * la rotation serveur en condamnait un, et la session tombait alors
           * que rien n'avait expiré.
           */
          final access = await VerrouRafraichissement.partage(() async {
            final tokens = await _repo.refresh(refresh);
            await _storage.saveTokens(
                access: tokens.accessToken, refresh: tokens.refreshToken);
            return tokens.accessToken;
          });
          /*
           * 🔴 `null` NE VEUT PAS DIRE « SESSION MORTE ».
           *
           * Le verrou rend `null` quand le rafraîchissement n'a pas abouti sans
           * que le serveur ait rien condamné — ou quand c'est un AUTRE appelant
           * qui tenait le verrou et que son travail n'a rien rendu. Basculer en
           * « non authentifié » ici afficherait l'écran de connexion à quelqu'un
           * dont la session est parfaitement valide : c'est exactement le
           * symptôme « on me redemande mes identifiants alors que je suis en
           * règle ».
           *
           * On retombe donc sur le profil en cache, comme partout ailleurs dans
           * cette méthode.
           */
          if (access == null) {
            if (user != null) {
              _set(AuthStatus.authenticated, user);
              return;
            }
            // Rien en cache : on ne sait pas. On montre la connexion SANS
            // effacer les jetons — le prochain démarrage pourra restaurer.
            _set(AuthStatus.unauthenticated, null);
            return;
          }
          final u = await _repo.me(access);
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
          // Un jeton copié a circulé. On ne dit PAS « ouvert sur un autre
          // appareil » : ce n'est pas ce qui s'est passé, et laisser croire à
          // une simple seconde connexion masquerait un incident de sécurité.
          if (e.code == "JETON_REJOUE") {
            messageDeconnexion =
                "Session fermée par sécurité. Reconnecte-toi.";
          }

          // Le serveur en panne n'est pas un refus — voir
          // [sessionMorteApresEchec], qui porte la règle et ses raisons.
          if (!sessionMorteApresEchec(e)) {
            if (user != null) {
              _set(AuthStatus.authenticated, user);
              return;
            }
            /*
             * ⚠️ PAS DE `rethrow` : il tombait dans le `catch` final, qui
             * EFFACE le stockage. Un démarrage sans profil en cache — première
             * ouverture après installation, cache vidé — pendant une panne
             * passagère détruisait donc des jetons parfaitement valides.
             *
             * On montre la connexion, mais on GARDE les jetons : le prochain
             * démarrage, réseau revenu, restaurera la session tout seul.
             */
            _set(AuthStatus.unauthenticated, null);
            return;
          }
        } catch (e) {
          /*
           * ⚠️ RÉSEAU COUPÉ, DÉLAI DÉPASSÉ, DNS : aucune réponse du serveur.
           *
           * Ces pannes-là arrivent en `SocketException` ou `ClientException`,
           * PAS en `ApiException` — elles ne passent donc pas par la branche
           * ci-dessus. Elles tombaient dans « Échec total », et démarrer
           * l'application hors réseau déconnectait.
           *
           * On garde la session : le profil en cache suffit à travailler, et le
           * rafraîchissement réussira au prochain réseau.
           */
          if (!sessionMorteApresEchec(e)) {
            if (user != null) {
              _set(AuthStatus.authenticated, user);
              return;
            }
            // Même raison que ci-dessus : on n'efface pas ce qu'on n'a pas pu
            // vérifier.
            _set(AuthStatus.unauthenticated, null);
            return;
          }
        }
      }

      /*
       * 4. Le serveur a NOMMÉ son refus — session évincée, jeton rejoué,
       *    révoquée, expirée — ou il n'y avait rien à restaurer.
       *
       * ⚠️ C'EST LE SEUL ENDROIT QUI A LE DROIT D'EFFACER. Tous les autres
       * chemins montrent la connexion en gardant les jetons : ils n'ont pas de
       * certitude, et effacer par précaution est précisément ce qui obligeait
       * des gens en règle à retaper leur mot de passe.
       */
      await _storage.clear();
      _set(AuthStatus.unauthenticated, null);
    } catch (_) {
      // Erreur de lecture du stockage sécurisé, ou réseau : si on a un profil
      // en cache, on reste authentifié.
      if (user != null) {
        _set(AuthStatus.authenticated, user);
        return;
      }
      /*
       * ⚠️ ON N'EFFACE PLUS ICI. On arrive dans ce `catch` pour des pannes qui
       * ne disent RIEN du jeton — le stockage sécurisé illisible au démarrage
       * en est le cas typique, et il est transitoire : le trousseau Android
       * n'est pas toujours prêt à la première milliseconde. Effacer alors
       * détruisait une session valide sur un incident de lecture.
       */
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
    // Les langues observées chez les correspondants d'un compte ne doivent pas
    // servir d'indice au compte suivant sur le même téléphone.
    await MemoireLangues.clear();
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
