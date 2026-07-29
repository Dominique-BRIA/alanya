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
