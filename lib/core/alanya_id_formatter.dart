/// Utilitaires de formatage de l'Alanya ID (numéro public).
///
/// Les longueurs supportées et leurs formats visuels :
/// - 3 chiffres  : xxx
/// - 4 chiffres  : xx xx
/// - 6 chiffres  : xxx xxx
/// - 8 chiffres  : xx xx xx xx
/// - 10 chiffres : x xxx xxx xxx

/// Formate un Alanya ID brut (uniquement des chiffres) pour l'affichage.
String formatAlanyaId(String rawId) {
  final digits = rawId.replaceAll(RegExp(r'\s+'), '');
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

/// Nettoie un Alanya ID formaté (supprime tous les espaces)
/// pour le transmettre au backend.
String stripAlanyaId(String formattedId) {
  return formattedId.replaceAll(RegExp(r'\s+'), '');
}
