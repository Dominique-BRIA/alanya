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

  /// Le badge du compte officiel quand le serveur dit `officiel` sans envoyer
  /// de badge. Sans adresse : seule l'image embarquée s'affiche.
  static const officielParDefaut =
      BadgeCompte(type: 'officiel', image: '', libelle: 'Compte officiel');

  /// L'image embarquée dans l'application pour ce type, s'il y en a une — la
  /// même que celle du serveur (`public/badges/`), copiée le 18/10/2026.
  ///
  /// 🐛 « LE BADGE DISPARAÎT TOUJOURS » (user, 18/10/2026) : tant que l'image
  /// du serveur n'était pas là — premier affichage, réseau lent, image
  /// illisible — le badge n'avait rien à montrer. L'image embarquée tient la
  /// place, puis celle du serveur la remplace si elle arrive.
  String? get imageEmbarquee => const {
        'officiel': 'assets/images/badges/officiel.png',
        'verifie': 'assets/images/badges/verifie.png',
      }[type];
}
