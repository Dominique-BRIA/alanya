/// Le badge à côté d'un nom, tel que le serveur le décide
/// (backend `src/lib/badges.ts`).
///
/// ⚠️ L'APPLICATION NE DÉCIDE RIEN (décision du user, 16/10/2026) : ni qui a un
/// badge, ni son image, ni son libellé. Elle dessine `image` avec `libelle`
/// en info-bulle. Tout se change côté serveur et console, sans mise à jour.
class BadgeCompte {
  /// `officiel`, `verifie`… — informatif : l'affichage n'en dépend pas.
  final String type;

  /// URL complète de l'image (PNG ou SVG).
  final String image;
  final String libelle;

  const BadgeCompte({required this.type, required this.image, required this.libelle});

  /// `null` si la charge n'en porte pas, ou une charge incomplète.
  static BadgeCompte? fromJson(Object? j) {
    if (j is! Map) return null;
    final image = j['image'];
    if (image is! String || image.isEmpty) return null;
    return BadgeCompte(
      type: (j['type'] as String?) ?? '',
      image: image,
      libelle: (j['libelle'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'image': image, 'libelle': libelle};
}
