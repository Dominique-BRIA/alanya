import '../../core/authed_api.dart';

/// Champs de profil renvoyés après mise à jour.
class ProfileUpdate {
  final String? pseudo;
  final String? avatarUrl;
  final String? statusMsg;
  ProfileUpdate({this.pseudo, this.avatarUrl, this.statusMsg});
}

class AccountRepository {
  AccountRepository(this._api);
  final AuthedApi _api;

  Future<ProfileUpdate> updateProfile({String? pseudo, String? statusMsg, String? avatarUrl}) async {
    final body = <String, dynamic>{};
    if (pseudo != null) body["pseudo"] = pseudo;
    if (statusMsg != null) body["statusMsg"] = statusMsg;
    if (avatarUrl != null) body["avatarUrl"] = avatarUrl;
    final data = await _api.patch("/api/account/profile", body);
    return ProfileUpdate(
      pseudo: data["pseudo"] as String?,
      avatarUrl: data["avatarUrl"] as String?,
      statusMsg: data["statusMsg"] as String?,
    );
  }

  /// Change le PAYS du compte.
  ///
  /// 🔴 NE TOUCHE NI À L'ALANYA ID NI AU NUMÉRO. Un numéro appartient à
  /// l'opérateur qui l'a attribué, pas au pays où l'on vit : déménager en
  /// gardant sa ligne est le cas normal, et renormaliser sur le nouvel
  /// indicatif transformerait un numéro juste en numéro faux.
  Future<void> changerPays(int idPays) async {
    await _api.patch("/api/account/profile", {"idPays": idPays});
  }

  /// Change le NUMÉRO DE TÉLÉPHONE, sous mot de passe.
  ///
  /// 🔴 `users.mobile` UNIQUEMENT — l'Alanya ID ne bouge jamais. C'est lui que
  /// les contacts ont enregistré et par lequel on appelle ; le changer
  /// détruirait le compte.
  ///
  /// ⚠️ La saisie part TELLE QUELLE. C'est le serveur qui normalise, avec la
  /// même règle qu'à l'inscription — et il respecte un « + » initial, donc une
  /// ligne étrangère garde son propre indicatif.
  ///
  /// Rend le numéro TEL QU'ENREGISTRÉ, pour que l'écran affiche ce que la base
  /// contient et non ce qui a été tapé.
  /// [idPaysNumero] : le pays DE LA LIGNE, quand il diffère de celui du compte.
  ///
  /// 🔴 IL N'EST JAMAIS ÉCRIT SUR LE COMPTE. Il ne sert qu'à donner le bon
  /// indicatif au numéro : normaliser une ligne camerounaise avec l'indicatif
  /// français d'un compte expatrié produisait « +33691234567 », injoignable.
  Future<String> changerMobile({
    required String motDePasse,
    required String mobile,
    int? idPaysNumero,
  }) async {
    final data = await _api.post("/api/account/mobile", {
      "password": motDePasse,
      "mobile": mobile,
      if (idPaysNumero != null) "idPaysNumero": idPaysNumero,
    });
    return data["mobile"] as String? ?? "";
  }

  /// Le mot de passe fourni est-il bien celui du compte ?
  ///
  /// Rend normalement, ou lève une [ApiException] — « Mot de passe incorrect »
  /// en 403, et un 429 si les essais s'enchaînent.
  ///
  /// ⚠️ NE DONNE AUCUN DROIT ET NE MODIFIE RIEN. Sert aux écrans qui se ferment
  /// derrière une confirmation : demander le mot de passe AVANT d'ouvrir
  /// l'écran, plutôt que de le découvrir faux à l'enregistrement, une fois le
  /// formulaire rempli. Le serveur le revérifie de toute façon à l'écriture —
  /// une porte côté client ne protège rien par elle-même.
  Future<void> verifierMotDePasse(String motDePasse) async {
    await _api.post("/api/account/verify-password", {"password": motDePasse});
  }

  /// Change le mot de passe de l'utilisateur connecté (vérifie l'actuel).
  /// Lève ApiException avec un message lisible en cas d'échec.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _api.post("/api/account/password", {
      "currentPassword": currentPassword,
      "newPassword": newPassword,
    });
  }

  /// Supprime définitivement le compte (vérifie le mot de passe).
  Future<void> deleteAccount(String password) async {
    await _api.delete("/api/account", body: {"password": password});
  }

  /// Réglages de confidentialité : {readReceipts (1/0), lastSeenVisibility (0/1/2)}.
  Future<Map<String, int>> getPrivacy() async {
    final data = await _api.get("/api/account/privacy");
    return {
      "readReceipts": (data["readReceipts"] as num?)?.toInt() ?? 1,
      "lastSeenVisibility": (data["lastSeenVisibility"] as num?)?.toInt() ?? 2,
    };
  }

  Future<void> setPrivacy({int? readReceipts, int? lastSeenVisibility}) async {
    final body = <String, dynamic>{};
    if (readReceipts != null) body["readReceipts"] = readReceipts;
    if (lastSeenVisibility != null) body["lastSeenVisibility"] = lastSeenVisibility;
    await _api.post("/api/account/privacy", body);
  }

  /// Historique des connexions du compte, de la plus récente à la plus
  /// ancienne. L'API ne renvoie jamais que les siennes.
  Future<List<LoginAccess>> loginHistory({int limit = 30}) async {
    final data = await _api.get("/api/user-access?limit=$limit");
    final brut = (data["acces"] as List?) ?? const [];
    return brut
        .map((e) => LoginAccess.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Une connexion enregistrée au journal.
class LoginAccess {
  const LoginAccess({
    required this.idLogin,
    required this.device,
    required this.ipAdress,
    required this.osSystem,
    required this.dateLogin,
  });

  final int idLogin;
  final String device;
  final String ipAdress;
  final String osSystem;
  final DateTime dateLogin;

  /// « INDEFINI » est la valeur du référentiel quand l'information manque :
  /// on ne l'affiche pas telle quelle à l'utilisateur.
  bool get deviceConnu => device != "INDEFINI";
  bool get systemeConnu => osSystem != "INDEFINI";
  bool get ipConnue => ipAdress != "INDEFINI" && ipAdress != "unknown";

  factory LoginAccess.fromJson(Map<String, dynamic> j) => LoginAccess(
        idLogin: (j["idLogin"] as num).toInt(),
        device: j["device"] as String? ?? "INDEFINI",
        ipAdress: j["ipAdress"] as String? ?? "INDEFINI",
        osSystem: j["osSystem"] as String? ?? "INDEFINI",
        dateLogin:
            DateTime.tryParse(j["dateLogin"] as String? ?? "") ?? DateTime.now(),
      );
}
