/// Analyseur de la mise en forme WhatsApp — **pur Dart, sans Flutter**.
///
/// Cette séparation n'est pas cosmétique : elle rend l'analyseur exécutable par
/// `dart run` hors du SDK Flutter, donc réellement testable sur ce poste, où
/// `flutter test` n'est pas disponible. Le rendu en `InlineSpan` vit dans
/// `whatsapp_text.dart`, qui ne fait plus que traduire l'arbre produit ici.
///
/// Marqueurs, identiques à WhatsApp :
///
/// | Saisie          | Rendu       |
/// |-----------------|-------------|
/// | `*texte*`       | gras        |
/// | `_texte_`       | italique    |
/// | `~texte~`       | barré       |
/// | ` ```texte``` ` | chasse fixe |
library;

enum StyleWhatsApp { gras, italique, barre, chasseFixe }

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

  /// Représentation de débogage, volontairement en ASCII : elle sert de forme
  /// attendue dans les tests, et des guillemets typographiques y seraient à la
  /// merci du moindre ré-encodage de fichier.
  @override
  String toString() =>
      texte != null ? '[$texte]' : '${style!.name}(${enfants.join()})';
}

const Map<String, StyleWhatsApp> _marqueurs = {
  '*': StyleWhatsApp.gras,
  '_': StyleWhatsApp.italique,
  '~': StyleWhatsApp.barre,
};

const String _chasseFixe = '```';

bool _estBlanc(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

/// Cherche le marqueur fermant correspondant à celui ouvert en [ouverture].
///
/// Renvoie -1 s'il n'y en a pas de valide : le marqueur ouvrant est alors
/// traité comme un caractère ordinaire, et reste donc visible.
///
/// Deux règles reprises de WhatsApp, qui évitent les faux positifs du langage
/// courant : le caractère suivant l'ouverture ne doit pas être un blanc — sans
/// quoi « 5 * 3 = 15 » passerait en gras — et celui précédant la fermeture non
/// plus. Le départ à +2 écarte le contenu vide (`**`).
int _chercheFermeture(String s, String marqueur, int ouverture, int fin) {
  if (ouverture + 1 >= fin || _estBlanc(s[ouverture + 1])) return -1;
  for (var j = ouverture + 2; j < fin; j++) {
    if (s[j] == marqueur && !_estBlanc(s[j - 1])) return j;
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
    // La chasse fixe prime : son contenu est pris littéralement, sinon un
    // extrait de code contenant une étoile partirait en gras.
    if (i + 3 <= fin && s.startsWith(_chasseFixe, i)) {
      final fermeture = s.indexOf(_chasseFixe, i + 3);
      if (fermeture != -1 && fermeture + 3 <= fin && fermeture > i + 3) {
        vider();
        noeuds.add(NoeudTexte.style(
          StyleWhatsApp.chasseFixe,
          [NoeudTexte.feuille(s.substring(i + 3, fermeture))],
        ));
        i = fermeture + 3;
        continue;
      }
    }

    final style = _marqueurs[s[i]];
    if (style != null) {
      final fermeture = _chercheFermeture(s, s[i], i, fin);
      if (fermeture != -1) {
        vider();
        // Récursion : les styles s'imbriquent.
        noeuds.add(NoeudTexte.style(style, _analyse(s, i + 1, fermeture)));
        i = fermeture + 1;
        continue;
      }
    }

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
