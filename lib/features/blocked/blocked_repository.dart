import '../../core/authed_api.dart';
import '../../models/blocked_user.dart';

/// Repository pour la gestion des utilisateurs bloqués (table « blocked » du PDF).
class BlockedRepository {
  final AuthedApi _api;

  BlockedRepository(this._api);

  /// Récupère la liste des utilisateurs bloqués.
  Future<List<BlockedUser>> fetchBlocked() async {
    final res = await _api.get("/api/blocked");
    final list = (res["blocked"] as List)
        .map((j) => BlockedUser.fromJson(j as Map<String, dynamic>))
        .toList();
    return list;
  }

  /// Bloque un utilisateur par son numéro public Alanya.
  ///
  /// Retourne le [BlockedUser] créé.
  Future<BlockedUser> blockUser(String publicNumber) async {
    final res = await _api.post("/api/blocked", {
      "publicNumber": publicNumber,
    });
    return BlockedUser.fromJson({
      ...res as Map<String, dynamic>,
      "pseudo": null,
      "publicNumber": publicNumber,
      "avatarUrl": null,
    });
  }

  /// Débloque un utilisateur par son idBlock.
  Future<void> unblockUser(int idBlock) async {
    await _api.delete("/api/blocked/$idBlock");
  }

  /// Vérifie si un utilisateur spécifique est bloqué (par idBlock).
  Future<BlockedUser?> checkBlocked(int idBlock) async {
    try {
      final res = await _api.get("/api/blocked/$idBlock");
      return BlockedUser.fromJson(res as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
