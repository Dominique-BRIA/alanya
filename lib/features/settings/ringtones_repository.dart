import 'dart:typed_data';

import '../../core/authed_api.dart';
import '../../models/sonnerie.dart';
import '../media/media_repository.dart';

/// Le catalogue de sonneries importées du compte.
///
/// ⚠️ L'import se fait en DEUX TEMPS, et c'est le contrat du serveur : on
/// téléverse d'abord le fichier (`POST /api/media`), puis on inscrit l'URL
/// obtenue au catalogue (`POST /api/ringtones`). Le second appel ne transporte
/// jamais d'octets — il ne fait que nommer un média déjà là.
class RingtonesRepository {
  RingtonesRepository(this._api, this._medias);
  final AuthedApi _api;
  final MediaRepository _medias;

  Future<List<Sonnerie>> list() async {
    final data = await _api.get("/api/ringtones");
    final brut = data["ringtones"] as List?;
    if (brut == null) return const [];
    return brut
        .whereType<Map<String, dynamic>>()
        .map(Sonnerie.fromJson)
        .toList();
  }

  /// Téléverse un fichier audio puis l'inscrit au catalogue.
  ///
  /// ⚠️ Le serveur rend **201 pour une nouvelle entrée, 200 quand l'URL y est
  /// déjà** — le libellé est alors mis à jour et la ligne existante rendue. « Un
  /// catalogue est un ensemble de médias, pas un journal d'imports. » Réimporter
  /// le même fichier ne crée donc pas de doublon, et l'appelant n'a rien à
  /// vérifier avant.
  Future<Sonnerie> importer({
    required Uint8List octets,
    required String nomFichier,
    required String typeMime,
    required String libelle,
    void Function(int envoyes, int total)? onProgress,
  }) async {
    final media = await _medias.upload(
      octets,
      nomFichier,
      typeMime,
      onProgress: onProgress,
    );
    final data = await _api.post("/api/ringtones", {
      // L'URL est envoyée TELLE QUELLE : le serveur exige la forme
      // `/api/media/<id>`, et c'est exactement ce que le téléversement rend.
      "url": media.url,
      "label": libelle,
    });
    return Sonnerie.fromJson(
        data["ringtone"] as Map<String, dynamic>? ?? const {});
  }

  Future<void> supprimer(String id) => _api.delete("/api/ringtones/$id");
}
