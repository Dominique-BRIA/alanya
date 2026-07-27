import 'package:flutter/services.dart';

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

/// Applique le formatage visuel de l'Alanya ID **pendant la saisie**, en
/// replaçant le curseur au bon endroit malgré les espaces insérés.
///
/// Extrait de `login_screen.dart`, où il ne servait qu'au champ de connexion,
/// pour que tous les champs qui reçoivent un Alanya ID se comportent
/// pareillement — sans quoi le même identifiant s'affiche formaté ici et collé
/// là.
///
/// Deux réglages selon le champ :
///  - [maxDigits] : nombre de chiffres au-delà duquel la frappe est refusée.
///    8 pour un champ Alanya ID (le serveur n'accepte que 6 ou 8), 10 pour un
///    champ tolérant.
///  - [allowNonDigits] : à `true`, une saisie contenant autre chose que des
///    chiffres et des espaces passe telle quelle — c'est le cas du champ mixte
///    « Alanya ID **ou** email » de la connexion. À `false`, tout caractère non
///    numérique est écarté, ce qui rend inutile un
///    `FilteringTextInputFormatter.digitsOnly` supplémentaire.
class AlanyaIdInputFormatter extends TextInputFormatter {
  const AlanyaIdInputFormatter({
    this.maxDigits = 8,
    this.allowNonDigits = false,
  });

  final int maxDigits;
  final bool allowNonDigits;

  static final _digit = RegExp(r'\d');
  static final _digitsOrSpaces = RegExp(r'^[\d\s]*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;

    // Champ mixte : dès qu'une lettre, un @ ou un point apparaît, c'est un
    // email — on n'y touche pas.
    if (allowNonDigits && raw.isNotEmpty && !_digitsOrSpaces.hasMatch(raw)) {
      return newValue;
    }

    final digitsOnly = stripAlanyaId(raw);
    // Limite dure : au-delà, la frappe est ignorée plutôt que tronquée, pour ne
    // pas déplacer silencieusement le curseur.
    if (digitsOnly.length > maxDigits) return oldValue;

    final formatted = formatAlanyaId(digitsOnly);

    // Le curseur est repositionné d'après le nombre de chiffres qui le
    // précèdent, seule référence stable quand des espaces sont insérés ou
    // retirés autour de lui.
    final oldCursor = newValue.selection.baseOffset.clamp(0, raw.length);
    var digitsBeforeCursor = 0;
    for (var i = 0; i < oldCursor; i++) {
      if (_digit.hasMatch(raw[i])) digitsBeforeCursor++;
    }
    var newCursor = 0;
    var seen = 0;
    while (newCursor < formatted.length && seen < digitsBeforeCursor) {
      if (_digit.hasMatch(formatted[newCursor])) seen++;
      newCursor++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}
