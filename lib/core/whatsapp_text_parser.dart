/// Analyseur de la mise en forme WhatsApp — **pur Dart, sans Flutter**.
///
/// Cette séparation n'est pas cosmétique : elle rend l'analyseur exécutable par
/// `dart run` hors du SDK Flutter, donc réellement testable sur ce poste, où
/// `flutter test` n'est pas disponible. Le rendu en `InlineSpan` vit dans
/// `whatsapp_text.dart`, qui ne fait plus que traduire l'arbre produit ici.
///
/// Marqueurs Alanya Work (évolution WhatsApp) :
///
/// | Saisie          | Rendu       | Icône    |
/// |-----------------|-------------|----------|
/// | `*texte*`       | gras        | B        |
/// | `_texte_`       | italique    | I        |
/// | `~texte~`       | barré       | S        |
/// | `__texte__`     | souligné    | U        |
/// | `` `texte` ``   | manuscrit   | ✍️       |
///
/// Le chasse fixe ```...``` (ancien <> ) a été retiré sur demande.
/// L'ordre de priorité est important : `__` (2 chars) avant `_` (1 char),
/// sinon `__hello__` serait vu comme `_` + `_hello_` + `_`.
library;

enum StyleWhatsApp { gras, italique, barre, souligne, manuscrit }

/// Un fragment de texte : soit une feuille ([texte] non nul), soit un style
/// appliqué à des [enfants].
class NoeudTexte {
  const NoeudTexte.feuille(String this.texte)
      : style = null,
        enfants = const [];

  const NoeudTexte.style(StyleWhatsApp this.style, this.enfants) : texte = null;

  final String? texte;
  final StyleWhatsApp? style;
  final List<NoeudTexte> enfants;

  @override
  String toString() =>
      texte != null ? '[$texte]' : '${style!.name}(${enfants.join()})';
}

class _DefMarqueur {
  const _DefMarqueur(this.code, this.style);
  final String code;
  final StyleWhatsApp style;
}

/// Ordre = priorité : plus long d'abord (__ avant _)
const List<_DefMarqueur> _defs = [
  _DefMarqueur('__', StyleWhatsApp.souligne),
  _DefMarqueur('*', StyleWhatsApp.gras),
  _DefMarqueur('_', StyleWhatsApp.italique),
  _DefMarqueur('~', StyleWhatsApp.barre),
  _DefMarqueur('`', StyleWhatsApp.manuscrit),
];

/// Cherche le marqueur fermant correspondant à celui ouvert en [ouverture].
///
/// Historiquement on refusait les blancs juste après l'ouvrant et juste avant
/// le fermant pour éviter « 5 * 3 ». Sur demande utilisateur on autorise
/// désormais les espaces : `* hello *` doit devenir gras.
/// - [code] peut faire 1 ou 2 caractères (__ , *, _, ~, `)
/// - Contenu vide interdit (ex. ** ou ____) → on exige au moins 1 char
int _chercheFermetureMulti(String s, String code, int ouverture, int fin) {
  final n = code.length;
  // besoin d'au moins 1 char entre ouvrant et fermant
  if (ouverture + n + 1 > fin - n) return -1;

  // Cherche le premier fermant valide après au moins 1 caractère intérieur.
  // On autorise les espaces autour du contenu.
  for (var j = ouverture + n + 1; j <= fin - n; j++) {
    if (s.startsWith(code, j)) {
      return j;
    }
  }
  return -1;
}

List<NoeudTexte> _analyse(String s, int debut, int fin) {
  final noeuds = <NoeudTexte>[];
  final tampon = StringBuffer();

  void vider() {
    if (tampon.isNotEmpty) {
      noeuds.add(NoeudTexte.feuille(tampon.toString()));
      tampon.clear();
    }
  }

  var i = debut;
  while (i < fin) {
    bool matched = false;
    for (final def in _defs) {
      final code = def.code;
      if (i + code.length <= fin && s.startsWith(code, i)) {
        final fermeture = _chercheFermetureMulti(s, code, i, fin);
        if (fermeture != -1) {
          vider();
          // Récursion : les styles s'imbriquent *_gras italique_* etc.
          noeuds.add(NoeudTexte.style(
            def.style,
            _analyse(s, i + code.length, fermeture),
          ));
          i = fermeture + code.length;
          matched = true;
          break;
        }
      }
    }
    if (matched) continue;

    tampon.write(s[i]);
    i++;
  }

  vider();
  return noeuds;
}

/// Découpe [source] en arbre de fragments stylés.
List<NoeudTexte> analyseWhatsApp(String source) =>
    _analyse(source, 0, source.length);

/// Retire les marqueurs sans appliquer de style.
///
/// Sert là où le texte doit tenir sur une ligne sans mise en forme : aperçu du
/// dernier message, citation d'une réponse, notification. Afficher `*coucou*`
/// à ces endroits exposerait la mécanique au lieu du message.
String sansMarqueursWhatsApp(String source) {
  final tampon = StringBuffer();
  void parcourir(List<NoeudTexte> noeuds) {
    for (final n in noeuds) {
      if (n.texte != null) {
        tampon.write(n.texte);
      } else {
        parcourir(n.enfants);
      }
    }
  }

  parcourir(analyseWhatsApp(source));
  return tampon.toString();
}
