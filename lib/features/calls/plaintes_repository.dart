import '../../core/authed_api.dart';

/// Dépôt d'une plainte vocale laissée sur la touche 0 d'un centre vocal.
///
/// ⚠️ Le contrat vit côté serveur (`src/app/api/complaints/route.ts`). Ce dépôt
/// ne fait que le traduire, il n'ajoute aucune règle.
class PlaintesRepository {
  PlaintesRepository(this._api);
  final AuthedApi _api;

  /// Rattache un média DÉJÀ téléversé à une plainte.
  ///
  /// 🔴 [cleEnvoi] REND L'ENVOI IDEMPOTENT, et elle vient du client. Une clé par
  /// enregistrement, posée à l'arrêt du micro et conservée jusqu'à la réussite :
  /// un réessai après un échec réseau, un double appui sur « Envoyer », ou une
  /// réponse perdue en route ne peuvent pas produire deux plaintes. Le serveur
  /// rend alors **200 avec la plainte déjà enregistrée** au lieu d'une erreur —
  /// du point de vue de l'appelant elle est bien partie, ce qui est vrai.
  ///
  /// ⚠️ La regénérer à chaque tentative annulerait toute la garantie : c'est
  /// exactement ce qu'il ne faut pas faire.
  Future<void> deposer({
    required String centerId,
    required String mediaId,
    required String cleEnvoi,
    int? dureeMs,
  }) async {
    await _api.post("/api/complaints", {
      "centerId": centerId,
      "mediaId": mediaId,
      "cleEnvoi": cleEnvoi,
      if (dureeMs != null) "dureeMs": dureeMs,
    });
  }
}
