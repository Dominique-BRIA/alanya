/// Calcul d'application des marqueurs WhatsApp — **pur Dart, sans Flutter**.
///
/// Séparé de `whatsapp_format_input.dart` pour la même raison que
/// l'analyseur : cette fonction fait de l'arithmétique d'indices sur le texte
/// que l'utilisateur est en train d'écrire. Une erreur d'un caractère y
/// corromprait un message sans rien signaler. En Dart pur, elle s'exécute par
/// `dart run` et se teste réellement.
library;

/// Nouveau texte et nouvelle sélection, après application d'un marqueur.
class ResultatMarqueur {
  const ResultatMarqueur(this.texte, this.debut, this.fin);

  final String texte;
  final int debut;
  final int fin;

  @override
  String toString() => '$texte|$debut,$fin';

  @override
  bool operator ==(Object other) =>
      other is ResultatMarqueur &&
      other.texte == texte &&
      other.debut == debut &&
      other.fin == fin;

  @override
  int get hashCode => Object.hash(texte, debut, fin);
}

/// Applique — ou retire — [code] autour de la plage `[debut, fin[` de [texte].
///
/// Trois situations, dans cet ordre :
///
/// 1. **Plage vide** (simple curseur) : insère les deux marqueurs et place le
///    curseur **entre les deux**, prêt à taper.
/// 2. **Plage déjà entourée** des marqueurs, qu'ils soient dedans ou juste
///    autour : ils sont retirés. Le bouton fait donc bascule et non
///    empilement — sinon un double appui produirait `**gras**`, que WhatsApp
///    interprète tout autrement.
/// 3. **Sinon** : la plage est enveloppée et reste sélectionnée.
ResultatMarqueur calculeMarqueur(
    String texte, int debut, int fin, String code) {
  // Bornes défensives : une sélection invalide vaut « à la fin du texte ».
  if (debut < 0 || debut > texte.length) debut = texte.length;
  if (fin < debut || fin > texte.length) fin = debut;

  final avant = texte.substring(0, debut);
  final choix = texte.substring(debut, fin);
  final apres = texte.substring(fin);
  final n = code.length;

  // 1. Curseur seul : on ouvre, on ferme, curseur au milieu.
  if (choix.isEmpty) {
    return ResultatMarqueur('$avant$code$code$apres', debut + n, debut + n);
  }

  // 2a. Les marqueurs sont DANS la sélection.
  if (choix.length > 2 * n && choix.startsWith(code) && choix.endsWith(code)) {
    final nu = choix.substring(n, choix.length - n);
    return ResultatMarqueur('$avant$nu$apres', debut, debut + nu.length);
  }

  // 2b. Les marqueurs ENCADRENT la sélection.
  if (avant.endsWith(code) && apres.startsWith(code)) {
    final nouveau =
        avant.substring(0, avant.length - n) + choix + apres.substring(n);
    return ResultatMarqueur(nouveau, debut - n, debut - n + choix.length);
  }

  // 3. Envelopper, en gardant le texte sélectionné.
  return ResultatMarqueur(
      '$avant$code$choix$code$apres', debut + n, debut + n + choix.length);
}
