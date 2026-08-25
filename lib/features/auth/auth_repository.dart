import '../../core/device_registry.dart';
import '../../core/api_client.dart';
import '../../models/auth_user.dart';

/// Résultat de la vérification OTP : token d'étape + numéro public attribué.
///
/// ⚠️ Rendu par DEUX chemins : `verify` (inscription avec adresse) et
/// `registerSansEmail` (inscription sans adresse). Le second porte en plus
/// [idRecuperation] ; le premier le laisse nul, l'adresse tenant ce rôle.
class VerifyResult {
  final String setupToken;
  final String publicNumber;
  final bool needsSetup;

  /// 🔴 MONTRÉ UNE SEULE FOIS, ET SEULEMENT ICI.
  ///
  /// C'est le seul moyen de reprendre un compte ouvert sans adresse. Le serveur
  /// ne le redonnera qu'à un utilisateur DÉJÀ connecté
  /// (`GET /api/account/recovery-id`) : si l'utilisateur quitte l'écran
  /// d'inscription sans l'avoir noté ET oublie son mot de passe avant de s'être
  /// reconnecté, son compte est perdu. L'écran DOIT donc le lui faire
  /// confirmer, pas seulement l'afficher.
  ///
  /// Nul pour une inscription avec adresse.
  final String? idRecuperation;

  VerifyResult(
    this.setupToken,
    this.publicNumber,
    this.needsSetup, {
    this.idRecuperation,
  });
}

/// Résultat d'une authentification réussie (setup ou login).
class AuthSession {
  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  /// Identifiants des appareils que cette connexion vient d'évincer.
  ///
  /// Le serveur les a déjà coupés en base ; cette liste sert seulement à les
  /// prévenir TOUT DE SUITE, sans quoi ils l'apprendraient à l'expiration de
  /// leur jeton d'accès — jusqu'à quinze minutes plus tard. L'API et le serveur
  /// temps réel étant deux process sans canal entre eux, c'est le client qui
  /// vient d'ouvrir la session qui fait le lien.
  final List<String> sessionsFermees;

  AuthSession(
    this.user,
    this.accessToken,
    this.refreshToken, {
    this.sessionsFermees = const [],
  });
}

/// Tokens rafraîchis (sans user – il faut rappeler /api/me après).
class RefreshSession {
  final String accessToken;
  final String refreshToken;
  RefreshSession(this.accessToken, this.refreshToken);
}

/// Appelle les endpoints d'authentification du backend.
class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  /// Étape 1 : demande l'envoi du code OTP par email.
  Future<void> register(String email) async {
    await _api.post("/api/auth/register", {"email": email});
  }

  /// Inscription SANS adresse : le compte est créé tout de suite.
  ///
  /// Il n'y a rien à confirmer, donc ni code ni écran OTP : le serveur rend
  /// directement le `setupToken` que rendait `verify`, et le parcours reprend à
  /// l'étape du mot de passe.
  ///
  /// ⚠️ Le champ `email` est ABSENT de la charge, pas vide : le serveur refuse
  /// `""` (une chaîne vide est une erreur de formulaire, ne rien envoyer est
  /// une intention).
  Future<VerifyResult> registerSansEmail() async {
    final data = await _api.post("/api/auth/register", const {});
    return VerifyResult(
      data["setupToken"] as String,
      data["publicNumber"] as String,
      (data["needsSetup"] as bool?) ?? true,
      idRecuperation: data["idRecuperation"] as String?,
    );
  }

  /// L'identifiant de récupération du compte connecté, ou `null` s'il n'en a
  /// pas (compte ouvert avec une adresse).
  ///
  /// ⚠️ À N'APPELER QU'APRÈS une confirmation biométrique : la réponse est un
  /// secret équivalent à un mot de passe.
  Future<({String? idRecuperation, bool aAdresse})> idRecuperation(
      String accessToken) async {
    final data =
        await _api.get("/api/account/recovery-id", bearer: accessToken);
    return (
      idRecuperation: data["idRecuperation"] as String?,
      aAdresse: (data["aAdresse"] as bool?) ?? false,
    );
  }

  /// Pose ou REMPLACE l'adresse du compte : premier temps, demande du code.
  ///
  /// 🔴 LE MOT DE PASSE COURANT EST EXIGÉ, pour ajouter comme pour remplacer.
  /// L'adresse EST un moyen de reprendre le compte : sans lui, quiconque
  /// emprunte une session ouverte y inscrit la sienne, puis reprend le compte
  /// plus tard par « mot de passe oublié ».
  ///
  /// ⚠️ Le code part sur la NOUVELLE adresse, jamais sur l'ancienne : c'est la
  /// nouvelle qu'il s'agit de prouver joignable, et l'ancienne est justement
  /// celle que l'utilisateur ne relève plus.
  Future<void> demanderAjoutEmail(
      String accessToken, String email, String motDePasse) async {
    await _api.post("/api/account/email", {"email": email, "password": motDePasse},
        bearer: accessToken);
  }

  /// Ajoute une adresse : confirme le code et pose l'adresse.
  Future<void> confirmerAjoutEmail(
      String accessToken, String email, String code) async {
    await _api.post("/api/account/email/verify", {"email": email, "code": code},
        bearer: accessToken);
  }

  /// Étape 2 : vérifie le code OTP à 6 chiffres.
  Future<VerifyResult> verify(String email, String code) async {
    final data =
        await _api.post("/api/auth/verify", {"email": email, "code": code});
    return VerifyResult(
      data["setupToken"] as String,
      data["publicNumber"] as String,
      (data["needsSetup"] as bool?) ?? true,
    );
  }

  /// Étape 3 : nom, téléphone et mot de passe (avec le setupToken).
  ///
  /// Le formulaire ne demande plus de pseudo — c'est le nom qui s'affiche
  /// partout. Il est recopié ici pour que le contrat d'API reste inchangé, et
  /// TRONQUÉ À 50 caractères : la colonne `users.pseudo` s'arrête là, alors que
  /// `nom` va jusqu'à 100. Sans cette coupe, un nom long passerait la
  /// validation du formulaire puis serait refusé par le serveur.
  Future<AuthSession> setup({
    required String setupToken,
    required String password,
    required String nom,
    String? mobile,
    int? idPays,
  }) async {
    final body = <String, dynamic>{
      "pseudo": nom.length > 50 ? nom.substring(0, 50) : nom,
      "password": password,
      "nom": nom,
    };
    if (mobile != null && mobile.isNotEmpty) body["mobile"] = mobile;
    if (idPays != null) body["idPays"] = idPays;
    body["deviceId"] = await DeviceRegistry.instance.deviceId();

    final data = await _api.post(
      "/api/auth/setup",
      body,
      bearer: setupToken,
    );
    return _session(data);
  }

  /// Connexion par email OU numéro public à 6 chiffres.
  Future<AuthSession> login(
      {required String identifier, required String password}) async {
    // `deviceId` rattache la session à cet appareil : c'est ce qui permet de la
    // révoquer depuis « Appareils connectés ». Sans lui, le serveur sait à quel
    // compte appartient le jeton, mais pas depuis quel appareil il a été émis.
    final data = await _api.post("/api/auth/login", {
      "identifier": identifier,
      "password": password,
      "deviceId": await DeviceRegistry.instance.deviceId(),
      // La FAMILLE de l'appareil, pour que le serveur n'évince que les autres
      // téléphones et laisse tranquille une session de bureau. À la toute
      // première connexion, l'appareil n'est pas encore au registre : sans cette
      // annonce, le serveur ne saurait pas à quelle famille il appartient et,
      // par prudence, n'évincerait personne.
      "typeDevice": DeviceRegistry.instance.typeDevice,
    });
    return _session(data);
  }

  /// Mot de passe oublié : déclenche l'envoi du code OTP.
  Future<void> forgotPassword(String email) async {
    await _api.post("/api/auth/forgot-password", {"email": email});
  }

  /// Réinitialisation du mot de passe avec le code OTP.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api.post("/api/auth/reset-password", {
      "email": email,
      "code": code,
      "password": newPassword,
    });
  }

  /// Réinitialise le mot de passe avec le CODE DE RÉCUPÉRATION **et** l'Alanya
  /// ID du compte.
  ///
  /// 🔴 LES DEUX SONT EXIGÉS. Le code seul suffisait au départ ; c'était un
  /// secret unique dont la fuite aurait ouvert tous les comptes sans adresse
  /// d'un coup. L'Alanya ID n'est pas un secret — les contacts le connaissent —
  /// mais il empêche la reprise EN MASSE : un code volé ne dit plus à quel
  /// compte il appartient.
  ///
  /// ⚠️ N'ENVOYER NI `email` NI `code` avec. Le serveur refuse explicitement un
  /// mélange des deux chemins plutôt que d'en choisir un — une demande ambiguë
  /// sur une route qui rend un compte doit être rejetée, pas devinée.
  ///
  /// Aucune des deux saisies n'a besoin d'être nettoyée ici : le serveur relève
  /// la casse, ignore les séparateurs, traduit les I/L/O mal lus et ne retient
  /// que les chiffres de l'Alanya ID. Un nettoyage local ferait une deuxième
  /// règle à tenir accordée avec la sienne.
  Future<void> resetPasswordParIdRecuperation({
    required String idRecuperation,
    required String alanyaId,
    required String newPassword,
  }) async {
    await _api.post("/api/auth/reset-password", {
      "idRecuperation": idRecuperation,
      "publicNumber": alanyaId,
      "password": newPassword,
    });
  }

  Future<AuthUser> me(String accessToken) async {
    final data = await _api.get("/api/me", bearer: accessToken);
    return AuthUser.fromJson(data);
  }

  /// Rafraîchit un access token expiré à partir du refresh token.
  /// Retourne les nouveaux tokens. Ne supprime rien en cas d'échec – c'est à l'appelant.
  Future<RefreshSession> refresh(String refreshToken) async {
    final data =
        await _api.post("/api/auth/refresh", {"refreshToken": refreshToken});
    return RefreshSession(
      data["accessToken"] as String,
      data["refreshToken"] as String,
    );
  }

  Future<void> logout(String refreshToken) async {
    await _api.post("/api/auth/logout", {"refreshToken": refreshToken});
  }

  AuthSession _session(Map<String, dynamic> data) => AuthSession(
        AuthUser.fromJson(data["user"] as Map<String, dynamic>),
        data["accessToken"] as String,
        data["refreshToken"] as String,
        // Absent d'un serveur plus ancien, et absent de `/setup` : la liste vide
        // est alors la vérité, aucune session n'ayant été fermée.
        sessionsFermees:
            (data["sessionsFermees"] as List?)?.whereType<String>().toList() ??
                const [],
      );
}
