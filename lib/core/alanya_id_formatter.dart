/// Utilitaires de formatage de l'Alanya ID (numéro public).
///
/// Les longueurs supportées et leurs formats visuels :
/// - 3 chiffres  : xxx
/// - 4 chiffres  : xx xx
/// - 6 chiffres  : xxx xxx
/// - 8 chiffres  : xx xx xx xx
/// - 10 chiffres : x xxx xxx xxx
///
/// Note : aujourd'hui le serveur n'émet que des IDs à 8 chiffres
/// (`generateUniquePublicNumber`), la colonne est en `VarChar(8)` et les
/// endpoints n'acceptent que 6 ou 8 chiffres. Les cas 3, 4 et 10 sont donc
/// injoignables avec des données réelles : ils ne sont conservés que pour ne
/// pas casser l'affichage si ces longueurs arrivaient un jour (une migration
/// de la colonne serait nécessaire au-delà de 8).

/// Formate un Alanya ID brut pour l'affichage.
///
/// Tolère une entrée déjà formatée : le nettoyage précède le découpage, donc
/// l'appel est idempotent.
String formatAlanyaId(String rawId) {
  final digits = stripAlanyaId(rawId);
  final len = digits.length;

  switch (len) {
    case 3:
      return digits; // xxx
    case 4:
      return '${digits.substring(0, 2)} ${digits.substring(2)}'; // xx xx
    case 6:
      return '${digits.substring(0, 3)} ${digits.substring(3)}'; // xxx xxx
    case 8:
      return '${digits.substring(0, 2)} ${digits.substring(2, 4)} ' +
          '${digits.substring(4, 6)} ${digits.substring(6)}'; // xx xx xx xx
    case 10:
      return '${digits.substring(0, 1)} ' +
          '${digits.substring(1, 4)} ' +
          '${digits.substring(4, 7)} ' +
          '${digits.substring(7)}'; // x xxx xxx xxx
    default:
      // Pour toute autre longueur, retombe sur un format standard
      // (espace tous les 2 chiffres) sans rupture.
      final buf = StringBuffer();
      for (int i = 0; i < digits.length; i++) {
        if (i > 0 && i % 2 == 0) buf.write(' ');
        buf.write(digits[i]);
      }
      return buf.toString();
  }
}

/// Nettoie un Alanya ID pour le transmettre au backend : ne conserve que les
/// chiffres.
///
/// À appeler sur **toute** saisie utilisateur avant validation, envoi,
/// comparaison ou mise en cache. Absorbe les espaces (y compris l'espace
/// insécable de certains claviers), mais aussi les tirets, points et
/// parenthèses qu'un copier-coller peut traîner : « 67-64-15-99 » comme
/// « 67 64 15 99 » donnent « 67641599 ».
String stripAlanyaId(String formattedId) {
  return formattedId.replaceAll(RegExp(r'\D'), '');
}
