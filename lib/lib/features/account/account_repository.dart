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
}
