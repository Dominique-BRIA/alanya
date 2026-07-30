import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// ALANYA DESIGN SYSTEM — Premium African-Inspired Theme
// =============================================================================
// Palette : terre cuite, brun chocolat, sable, vert forêt, or doux.
// Inspirée des motifs tissés africains et de la terre rouge camerounaise.
// =============================================================================

// ---------------------------------------------------------------------------
// COULEURS PRINCIPALES
// ---------------------------------------------------------------------------
class AlanyaColors {
  AlanyaColors._();

  // --- Terre cuite (Primary) ---
  static const Color terracotta      = Color(0xFFB85C38);
  static const Color terracottaLight = Color(0xFFD4845E);
  static const Color terracottaDark  = Color(0xFF8A3A1E);

  // --- Brun chocolat (Secondary) ---
  static const Color chocolate      = Color(0xFF5C3D2E);
  static const Color chocolateLight = Color(0xFF8B6B5A);

  // --- Vert forêt (Accent) ---
  static const Color forest      = Color(0xFF2D6A4F);
  static const Color forestLight = Color(0xFF52B788);
  static const Color forestDark  = Color(0xFF1B4332);

  // --- Sable & Crème (Surface) ---
  static const Color sand       = Color(0xFFF0E6D8);
  static const Color cream      = Color(0xFFFAF6F0);
  static const Color warmWhite  = Color(0xFFFFFCF8);

  // --- Or doux ---
  static const Color gold       = Color(0xFFD4A574);
  static const Color goldLight  = Color(0xFFF0D5B8);

  // --- Thème NUIT (mode sombre — système visuel Alanya) ---
  static const Color nuit        = Color(0xFF0B0B18); // fond page
  static const Color nuit2       = Color(0xFF14142A); // surface / cartes
  static const Color nuit3       = Color(0xFF1E1E3D); // surface élevée
  static const Color indigo      = Color(0xFF3B3B7A); // accent indigo
  static const Color indigoLight = Color(0xFF7C7CD8);
  static const Color terracottaNuit      = Color(0xFFC56A42); // accent terre cuite (nuit)
  static const Color terracottaNuitLight = Color(0xFFE29A74);
  static const Color braise      = Color(0xFFA33F2E); // rouge braise (destructif/raccrocher)
  static const Color craie       = Color(0xFFEDE7DF); // texte principal
  static const Color craie2      = Color(0xFF9A96AC); // texte secondaire
  static const Color ligne       = Color(0x247C7CD8); // filets : indigo translucide
  static const Color erreurNuit  = Color(0xFFEF6B60); // destructif lisible sur nuit

  // --- Thème NOIR (3e thème — base noire, accent teal) ---
  // Palette distincte de Nuit : là où Nuit est un indigo-nuit avec accents
  // terre cuite, Noir est un vrai noir OLED avec un seul accent teal.
  static const Color noir         = Color(0xFF000000); // fond page — pixels éteints sur OLED
  static const Color noir2        = Color(0xFF0D0D0D); // barres, composeur
  static const Color noir3        = Color(0xFF1C1C1E); // cartes, surfaces élevées
  static const Color noirChamp    = Color(0xFF1A1A1A); // champs de saisie
  static const Color teal         = Color(0xFF008B8B); // accent unique
  static const Color tealSombre   = Color(0xFF00494A); // bulle envoyée
  static const Color noirTexte    = Color(0xFFFFFFFF); // texte principal
  static const Color noirTexte2   = Color(0xFF8E8E93); // texte secondaire
  static const Color noirLigne    = Color(0xFF3A3A3C); // filets et bordures
  static const Color erreurNoir   = Color(0xFFFF6B6B); // destructif sur noir

  // --- Thème BLANC (4e thème — base blanche, accent teal, terre cuite en 2d) ---
  // Là où « Clair » est chaud (crème, sable, terre cuite), « Blanc » est net et
  // froid : fond blanc pur, accent teal. Le terre cuite y reste présent comme
  // couleur SECONDAIRE, ce qui garde le lien avec l'identité d'Alanya.
  static const Color blancSurfaceH  = Color(0xFFF7F7F7); // surface élevée
  static const Color blancChamp     = Color(0xFFF2F2F2); // champ de saisie
  static const Color blancRecue     = Color(0xFFEFEFEF); // bulle reçue
  static const Color blancEnvoyee   = Color(0xFFD6ECEC); // bulle envoyée, teinte du teal
  static const Color blancTexte     = Color(0xFF16181A); // texte principal, neutre
  static const Color blancTexte2    = Color(0xFF8A8A8E); // horodatages, secondaire
  static const Color blancLigne     = Color(0xFFE5E5EA); // filets

  // --- Neutres chauds ---
  static const Color ink        = Color(0xFF1A1210);
  static const Color inkLight   = Color(0xFF3D322C);
  static const Color grey50     = Color(0xFFFAF8F6);
  static const Color grey100    = Color(0xFFF5F0EB);
  static const Color grey200    = Color(0xFFE8DFD6);
  static const Color grey300    = Color(0xFFD4C8BC);
  static const Color grey400    = Color(0xFFB0A090);
  static const Color grey500    = Color(0xFF8C7A68);
  static const Color grey600    = Color(0xFF6B5A4A);
  static const Color grey700    = Color(0xFF4A3D32);
  static const Color grey800    = Color(0xFF2E241C);
  static const Color grey900    = Color(0xFF1A1210);

  // --- Sémantiques ---
  static const Color success    = Color(0xFF2D6A4F);
  static const Color successBg  = Color(0xFFE8F5E9);
  static const Color warning    = Color(0xFFE8A317);
  static const Color warningBg  = Color(0xFFFFF8E1);
  static const Color error      = Color(0xFFC62828);
  static const Color errorBg    = Color(0xFFFFEBEE);
  static const Color info       = Color(0xFF1565C0);
  static const Color infoBg     = Color(0xFFE3F2FD);

  // --- Chat ---
  static const Color bubbleMe     = Color(0xFFB85C38);
  static const Color bubbleOther  = Color(0xFFFFFFFF);
  static const Color tickDelivered = Color(0xFF9E9E9E);
  static const Color tickRead     = Color(0xFF52B788);

  // --- Avatar gradients ---
  static const List<Color> avatarGradients = [
    Color(0xFFB85C38),
    Color(0xFFD4845E),
    Color(0xFF5C3D2E),
    Color(0xFF2D6A4F),
    Color(0xFFD4A574),
    Color(0xFF8B6B5A),
    Color(0xFF52B788),
    Color(0xFFE8A317),
  ];
}

// ---------------------------------------------------------------------------
// SÉLECTEUR CLAIR / NUIT
// ---------------------------------------------------------------------------
/// Renvoie [dark] en mode Nuit, [light] sinon.
///
/// Le chantier « mode sombre » ne doit RIEN changer au mode clair : à chaque
/// appel on reconduit la couleur claire d'origine telle quelle et on n'ajoute
/// que sa variante Nuit. Ne pas remplacer une couleur claire en dur par un
/// jeton du colorScheme : les valeurs ne coïncident pas toujours
/// (ex. surface = warmWhite ≠ Colors.white, onSurfaceVariant = grey600 ≠ black54).
/// Les quatre variantes d'Alanya.
///
/// Deux claires et deux sombres. `Theme.of(context).brightness` ne distingue
/// que clair/sombre : c'est cette énumération, portée par [AlanyaSurfaces],
/// qui permet de savoir LAQUELLE des deux est active.
enum VarianteTheme { clair, blanc, nuit, noir }

/// Surfaces propres à chaque thème, portées par le ThemeData lui-même.
///
/// **Pourquoi une ThemeExtension plutôt que des constantes.** Le code appelait
/// `AlanyaColors.nuit / nuit2 / nuit3` en dur à 54 endroits. Ces valeurs sont
/// justes pour Nuit et fausses pour Noir, mais un simple `if` supplémentaire à
/// chaque site aurait été intenable — et surtout risqué : remplacer des
/// couleurs en dur par des jetons approchants est exactement ce qui avait fait
/// dériver le mode clair en juillet.
///
/// Ici, chaque thème déclare SES valeurs. Nuit reçoit très exactement celles
/// qu'il avait, au bit près, donc il ne peut pas bouger.
@immutable
class AlanyaSurfaces extends ThemeExtension<AlanyaSurfaces> {
  const AlanyaSurfaces({
    required this.fond,
    required this.surface,
    required this.surfaceHaute,
    required this.champ,
    required this.bulleRecue,
    required this.texteBulleRecue,
    required this.bulleEnvoyee,
    required this.texteBulleEnvoyee,
    required this.avecMotif,
    required this.variante,
  });

  /// Fond de page — l'ancien `AlanyaColors.nuit`.
  final Color fond;

  /// Cartes, barres, composeur — l'ancien `AlanyaColors.nuit2`.
  final Color surface;

  /// Surface élevée — l'ancien `AlanyaColors.nuit3`.
  final Color surfaceHaute;

  /// Champs de saisie.
  final Color champ;

  final Color bulleRecue;
  final Color texteBulleRecue;
  final Color bulleEnvoyee;
  final Color texteBulleEnvoyee;

  /// Le motif de fond s'affiche-t-il ? Faux en Noir : un motif rallume des
  /// pixels sur toute la surface et annule le gain OLED, qui est la raison
  /// d'être du thème.
  final bool avecMotif;

  /// Laquelle des quatre variantes est active.
  ///
  /// Une valeur explicite plutôt qu'une comparaison de couleur : pendant
  /// l'animation de changement de thème les couleurs sont interpolées, et
  /// `fond == #000000` ne deviendrait vrai qu'à la toute fin, provoquant un
  /// saut d'accent en fin de transition.
  final VarianteTheme variante;

  /// Valeurs du thème Nuit — reprises telles quelles de l'existant.
  static const nuit = AlanyaSurfaces(
    fond: AlanyaColors.nuit,
    surface: AlanyaColors.nuit2,
    surfaceHaute: AlanyaColors.nuit3,
    champ: AlanyaColors.nuit2,
    // Ces quatre valeurs sont relevées sur le code existant du fil de
    // discussion, pas choisies : bulle reçue en nuit3, envoyée en indigo,
    // texte craie côté reçu et blanc côté envoyé. Toute autre valeur ferait
    // dériver Nuit dès que les getters seront branchés dessus.
    bulleRecue: AlanyaColors.nuit3,
    texteBulleRecue: AlanyaColors.craie,
    bulleEnvoyee: AlanyaColors.indigo,
    texteBulleEnvoyee: Colors.white,
    avecMotif: true,
    variante: VarianteTheme.nuit,
  );

  /// Valeurs du thème Noir.
  static const noir = AlanyaSurfaces(
    fond: AlanyaColors.noir,
    surface: AlanyaColors.noir2,
    surfaceHaute: AlanyaColors.noir3,
    champ: AlanyaColors.noirChamp,
    // Bulles reçues BLANCHES à texte noir, comme demandé. C'est le contraste
    // le plus fort possible ; il distingue immédiatement reçu et envoyé.
    bulleRecue: Colors.white,
    texteBulleRecue: AlanyaColors.ink,
    bulleEnvoyee: AlanyaColors.tealSombre,
    texteBulleEnvoyee: Colors.white,
    avecMotif: false,
    variante: VarianteTheme.noir,
  );

  /// Valeurs du thème Blanc : base blanche nette, accent teal, bulle reçue en
  /// gris clair et envoyée dans une teinte du teal. Pas de motif — la
  /// référence visuelle est une surface blanche unie.
  static const blanc = AlanyaSurfaces(
    fond: Colors.white,
    surface: Colors.white,
    surfaceHaute: AlanyaColors.blancSurfaceH,
    champ: AlanyaColors.blancChamp,
    bulleRecue: AlanyaColors.blancRecue,
    texteBulleRecue: AlanyaColors.blancTexte,
    // Le teal PLEIN, celui du bouton d'envoi, et non plus la teinte pâle
    // `blancEnvoyee` : les deux éléments portent la même action, ils doivent
    // porter la même couleur.
    bulleEnvoyee: AlanyaColors.teal,
    texteBulleEnvoyee: Colors.white,
    avecMotif: false,
    variante: VarianteTheme.blanc,
  );

  /// Valeurs du mode clair. Présentes pour que l'accesseur ne renvoie jamais
  /// nul : aucun site d'appel n'a besoin de tester la nullité.
  static const clair = AlanyaSurfaces(
    fond: AlanyaColors.cream,
    surface: Colors.white,
    surfaceHaute: AlanyaColors.warmWhite,
    champ: Colors.white,
    // Idem : relevé sur l'existant du mode clair, qui est figé.
    bulleRecue: Colors.white,
    texteBulleRecue: AlanyaColors.ink,
    bulleEnvoyee: AlanyaColors.terracotta,
    texteBulleEnvoyee: Colors.white,
    avecMotif: true,
    variante: VarianteTheme.clair,
  );

  @override
  AlanyaSurfaces copyWith({
    Color? fond,
    Color? surface,
    Color? surfaceHaute,
    Color? champ,
    Color? bulleRecue,
    Color? texteBulleRecue,
    Color? bulleEnvoyee,
    Color? texteBulleEnvoyee,
    bool? avecMotif,
    VarianteTheme? variante,
  }) =>
      AlanyaSurfaces(
        fond: fond ?? this.fond,
        surface: surface ?? this.surface,
        surfaceHaute: surfaceHaute ?? this.surfaceHaute,
        champ: champ ?? this.champ,
        bulleRecue: bulleRecue ?? this.bulleRecue,
        texteBulleRecue: texteBulleRecue ?? this.texteBulleRecue,
        bulleEnvoyee: bulleEnvoyee ?? this.bulleEnvoyee,
        texteBulleEnvoyee: texteBulleEnvoyee ?? this.texteBulleEnvoyee,
        avecMotif: avecMotif ?? this.avecMotif,
        variante: variante ?? this.variante,
      );

  @override
  AlanyaSurfaces lerp(ThemeExtension<AlanyaSurfaces>? other, double t) {
    if (other is! AlanyaSurfaces) return this;
    return AlanyaSurfaces(
      fond: Color.lerp(fond, other.fond, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHaute: Color.lerp(surfaceHaute, other.surfaceHaute, t)!,
      champ: Color.lerp(champ, other.champ, t)!,
      bulleRecue: Color.lerp(bulleRecue, other.bulleRecue, t)!,
      texteBulleRecue: Color.lerp(texteBulleRecue, other.texteBulleRecue, t)!,
      bulleEnvoyee: Color.lerp(bulleEnvoyee, other.bulleEnvoyee, t)!,
      texteBulleEnvoyee:
          Color.lerp(texteBulleEnvoyee, other.texteBulleEnvoyee, t)!,
      // Un booléen ne s'interpole pas : on bascule à mi-parcours.
      avecMotif: t < 0.5 ? avecMotif : other.avecMotif,
      variante: t < 0.5 ? variante : other.variante,
    );
  }
}

/// Surfaces du thème courant. Ne renvoie jamais nul — les trois thèmes
/// déclarent l'extension.
AlanyaSurfaces surfacesOf(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<AlanyaSurfaces>() ??
      (theme.brightness == Brightness.dark
          ? AlanyaSurfaces.nuit
          : AlanyaSurfaces.clair);
}

/// Vrai si le thème courant est « Noir ».
///
/// À n'utiliser que pour les rares cas qu'aucune couleur ne couvre — un
/// changement d'ASSET par exemple. Pour une couleur, passer par
/// [surfacesOf] : c'est le seul moyen de garantir que Nuit ne dérive pas.
bool estNoir(BuildContext context) =>
    surfacesOf(context).variante == VarianteTheme.noir;

/// Vrai si le thème courant est « Blanc ».
bool estBlanc(BuildContext context) =>
    surfacesOf(context).variante == VarianteTheme.blanc;

/// Choisit entre les deux thèmes CLAIRS. Les thèmes sombres ne passent jamais
/// ici. Pendant du helper `_sombre` plus bas.
Color _clairVariante(BuildContext context,
        {required Color clair, required Color blanc}) =>
    estBlanc(context) ? blanc : clair;

Color themed(BuildContext context,
        {required Color light, required Color dark}) =>
    Theme.of(context).brightness == Brightness.dark ? dark : light;

/// Choisit entre les deux thèmes SOMBRES. Le mode clair ne passe jamais ici.
///
/// C'est le pivot du troisième thème : en le glissant dans la branche `dark`
/// des helpers ci-dessous, les 218 sites qui les appellent basculent en Noir
/// sans qu'aucun ne soit modifié.
Color _sombre(BuildContext context, {required Color nuit, required Color noir}) =>
    estNoir(context) ? noir : nuit;

/// Accent d'action, par thème : terre cuite en Clair, **teal en Blanc**,
/// terre cuite Nuit en Nuit, teal en Noir.
///
/// En Blanc, le terre cuite n'est pas abandonné : il devient la couleur
/// SECONDAIRE et reste posé en dur là où il porte l'identité (bandeau de
/// notification, dégradés). Seul l'accent d'action passe au teal.
Color accentOf(BuildContext context) => themed(context,
    light: _clairVariante(context,
        clair: AlanyaColors.terracotta, blanc: AlanyaColors.teal),
    dark: _sombre(context,
        nuit: AlanyaColors.terracottaNuit, noir: AlanyaColors.teal));

/// Texte secondaire. La couleur claire reste à fournir : les écrans
/// n'utilisent pas tous le même gris (`black54`, `grey500`, `grey600`…) et on
/// ne doit pas les uniformiser au passage.
Color mutedOf(BuildContext context, Color light) => themed(context,
    light: light,
    dark: _sombre(context,
        nuit: AlanyaColors.craie2, noir: AlanyaColors.noirTexte2));

/// Texte « Alanya ID » et le numéro qui l'accompagne : **blanc franc en Nuit**.
///
/// C'est un identifiant qu'on lit pour le recopier ou le dicter, pas un
/// sous-titre décoratif — le gris `craie2` y était inutilement discret. Comme
/// pour [mutedOf], la couleur claire est passée en paramètre et reconduite
/// telle quelle : le mode clair ne bouge pas.
Color alanyaIdOf(BuildContext context, Color light) =>
    themed(context, light: light, dark: Colors.white);

/// Variante pour les écrans où l'Alanya ID n'avait **aucune** couleur explicite
/// (sous-titre de `ListTile`, qui hérite du thème).
///
/// Renvoyer `null` en clair est délibéré : le style d'origine reste appliqué
/// intégralement, donc rien ne peut dériver. En Nuit, seule la couleur est
/// surchargée — `Text` fusionne ce style avec celui hérité, la taille et la
/// graisse d'origine sont conservées.
TextStyle? alanyaIdStyleOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const TextStyle(color: Colors.white)
        : null;

/// Élément volontairement très discret (grande icône d'état vide, filigrane).
Color faintOf(BuildContext context, Color light) => themed(context,
    light: light,
    dark: _sombre(context,
        nuit: AlanyaColors.craie2.withValues(alpha: 0.4),
        noir: AlanyaColors.noirTexte2.withValues(alpha: 0.4)));

/// Destructif : rouge d'origine en clair, rouge lisible sur nuit sinon.
Color dangerOf(BuildContext context, [Color light = Colors.red]) =>
    themed(context,
        light: light,
        dark: _sombre(context,
            nuit: AlanyaColors.erreurNuit, noir: AlanyaColors.erreurNoir));

/// Vert forêt en clair. En Nuit il devient indigo clair : le `#2D6A4F` tombe
/// sous le seuil de contraste sur le fond nuit, et l'indigo porte l'identité.
Color positiveOf(BuildContext context) => themed(context,
    light: AlanyaColors.forest,
    dark: _sombre(context,
        nuit: AlanyaColors.indigoLight, noir: AlanyaColors.teal));

// ---------------------------------------------------------------------------
// LIGHT THEME
// ---------------------------------------------------------------------------
class AlanyaTheme {
  AlanyaTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: AlanyaColors.terracotta,
      onPrimary: Colors.white,
      primaryContainer: AlanyaColors.terracottaLight,
      onPrimaryContainer: AlanyaColors.terracottaDark,
      secondary: AlanyaColors.forest,
      onSecondary: Colors.white,
      secondaryContainer: AlanyaColors.forestLight,
      onSecondaryContainer: AlanyaColors.forestDark,
      tertiary: AlanyaColors.gold,
      onTertiary: Colors.white,
      surface: AlanyaColors.warmWhite,
      onSurface: AlanyaColors.ink,
      onSurfaceVariant: AlanyaColors.grey600,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AlanyaColors.grey50,
      surfaceContainer: AlanyaColors.grey100,
      surfaceContainerHigh: AlanyaColors.grey200,
      surfaceContainerHighest: AlanyaColors.grey300,
      outline: AlanyaColors.grey300,
      outlineVariant: AlanyaColors.grey200,
      error: AlanyaColors.error,
      onError: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AlanyaColors.cream,

      // --- Typography ---
      textTheme: _buildTextTheme(Brightness.light),
      extensions: const [AlanyaSurfaces.clair],

      // --- AppBar ---
      appBarTheme: AppBarTheme(
        backgroundColor: AlanyaColors.warmWhite,
        foregroundColor: AlanyaColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.ink,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AlanyaColors.ink),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      // --- NavigationBar ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AlanyaColors.warmWhite,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AlanyaColors.terracotta.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AlanyaColors.terracotta, size: 24);
          }
          return IconThemeData(color: AlanyaColors.grey400, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AlanyaColors.terracotta,
              letterSpacing: 0.2,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AlanyaColors.grey400,
          );
        }),
      ),

      // --- ElevatedButton ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AlanyaColors.terracotta,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // --- OutlinedButton ---
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AlanyaColors.terracotta,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: AlanyaColors.terracotta.withValues(alpha: 0.4)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // --- TextButton ---
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AlanyaColors.terracotta,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // --- InputDecoration ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(
          color: AlanyaColors.grey400,
          fontWeight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AlanyaColors.grey200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AlanyaColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.terracotta, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AlanyaColors.error.withValues(alpha: 0.5)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.error, width: 1.5),
        ),
      ),

      // --- Card ---
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AlanyaColors.grey200, width: 0.5),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // --- Divider ---
      dividerTheme: DividerThemeData(
        color: AlanyaColors.grey200,
        thickness: 0.5,
        space: 1,
      ),

      // --- SnackBar ---
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AlanyaColors.ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // --- BottomSheet ---
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AlanyaColors.warmWhite,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: AlanyaColors.grey300,
      ),

      // --- Dialog ---
      dialogTheme: DialogThemeData(
        backgroundColor: AlanyaColors.warmWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.ink,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AlanyaColors.grey600,
        ),
      ),

      // --- Chip ---
      chipTheme: ChipThemeData(
        backgroundColor: AlanyaColors.grey100,
        selectedColor: AlanyaColors.terracotta.withValues(alpha: 0.12),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AlanyaColors.grey700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // --- ListTile ---
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AlanyaColors.ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AlanyaColors.grey500,
        ),
      ),

      // --- FloatingActionButton ---
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AlanyaColors.terracotta,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // --- ProgressIndicator ---
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AlanyaColors.terracotta,
        linearTrackColor: AlanyaColors.sand,
      ),
    );
  }

  /// Quatrième thème : **Blanc**. Base blanche nette, accent teal `#008B8B`,
  /// terre cuite conservé en couleur secondaire.
  ///
  /// Sa `brightness` est `light`, comme Clair : les sites qui écrivent
  /// `themed(context, light: …, dark: …)` prennent donc la même branche dans
  /// les deux thèmes clairs. C'est voulu — la plupart de ces valeurs sont des
  /// blancs et des gris, identiques ici. Ce qui distingue vraiment Blanc de
  /// Clair passe par ce ColorScheme, par la ThemeExtension et par accentOf().
  static ThemeData get blanc {
    final colorScheme = ColorScheme.light(
      primary: AlanyaColors.teal,
      onPrimary: Colors.white,
      primaryContainer: AlanyaColors.blancEnvoyee,
      onPrimaryContainer: AlanyaColors.tealSombre,
      // Le terre cuite en SECONDAIRE : c'est ce qui garde le lien avec
      // l'identité d'Alanya alors que l'accent principal a changé.
      secondary: AlanyaColors.terracotta,
      onSecondary: Colors.white,
      secondaryContainer: AlanyaColors.terracottaLight,
      onSecondaryContainer: AlanyaColors.terracottaDark,
      tertiary: AlanyaColors.gold,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: AlanyaColors.blancTexte,
      onSurfaceVariant: AlanyaColors.blancTexte2,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AlanyaColors.blancSurfaceH,
      surfaceContainer: AlanyaColors.blancChamp,
      surfaceContainerHigh: AlanyaColors.blancRecue,
      surfaceContainerHighest: AlanyaColors.blancLigne,
      outline: AlanyaColors.blancLigne,
      outlineVariant: AlanyaColors.blancLigne,
      error: AlanyaColors.error,
      onError: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      textTheme: _buildTextTheme(
        Brightness.light,
        corps: AlanyaColors.blancTexte,
        attenue: AlanyaColors.blancTexte2,
      ),
      extensions: const [AlanyaSurfaces.blanc],

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AlanyaColors.blancTexte,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.blancTexte,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AlanyaColors.blancTexte),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AlanyaColors.teal.withValues(alpha: 0.14),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AlanyaColors.teal, size: 24);
          }
          return const IconThemeData(color: AlanyaColors.blancTexte2, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AlanyaColors.teal,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AlanyaColors.blancTexte2,
          );
        }),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AlanyaColors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AlanyaColors.teal,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: AlanyaColors.teal.withValues(alpha: 0.4)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AlanyaColors.teal,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AlanyaColors.blancChamp,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AlanyaColors.blancTexte2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.blancLigne),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.blancLigne),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.teal, width: 1.5),
        ),
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AlanyaColors.blancLigne, width: 0.5),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      dividerTheme: const DividerThemeData(
        color: AlanyaColors.blancLigne,
        thickness: 0.5,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AlanyaColors.blancTexte,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: AlanyaColors.blancLigne,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.blancTexte,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AlanyaColors.blancTexte2,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AlanyaColors.blancChamp,
        selectedColor: AlanyaColors.teal.withValues(alpha: 0.14),
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AlanyaColors.blancTexte,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AlanyaColors.blancTexte,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AlanyaColors.blancTexte2,
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AlanyaColors.teal,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AlanyaColors.teal,
        linearTrackColor: AlanyaColors.blancLigne,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DARK THEME
  // ---------------------------------------------------------------------------
  static ThemeData get dark {
    // Système visuel « Nuit » : base indigo-nuit, accents terre cuite + indigo.
    const darkBg = AlanyaColors.nuit;         // #0B0B18
    const darkSurface = AlanyaColors.nuit2;    // #14142A
    const darkSurfaceHigh = AlanyaColors.nuit3; // #1E1E3D

    final colorScheme = ColorScheme.dark(
      primary: AlanyaColors.terracottaNuit,
      onPrimary: Colors.white,
      primaryContainer: AlanyaColors.braise,
      onPrimaryContainer: AlanyaColors.craie,
      secondary: AlanyaColors.indigoLight,
      onSecondary: Colors.white,
      secondaryContainer: AlanyaColors.indigo,
      onSecondaryContainer: AlanyaColors.craie,
      tertiary: AlanyaColors.terracottaNuitLight,
      onTertiary: AlanyaColors.nuit,
      surface: darkSurface,
      onSurface: AlanyaColors.craie,
      onSurfaceVariant: AlanyaColors.craie2,
      surfaceContainerLowest: AlanyaColors.nuit,
      surfaceContainerLow: darkSurface,
      surfaceContainer: darkSurfaceHigh,
      surfaceContainerHigh: darkSurfaceHigh,
      surfaceContainerHighest: const Color(0xFF272750),
      outline: const Color(0xFF2E2E52),
      // « ligne » du modèle : indigo clair très translucide, jamais un gris.
      outlineVariant: AlanyaColors.ligne,
      error: AlanyaColors.erreurNuit,
      onError: Colors.white,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      textTheme: _buildTextTheme(Brightness.dark),
      extensions: const [AlanyaSurfaces.nuit],

      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: AlanyaColors.craie,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.craie,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AlanyaColors.terracottaNuit.withValues(alpha: 0.20),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AlanyaColors.terracottaNuitLight, size: 24);
          }
          return const IconThemeData(color: AlanyaColors.craie2, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AlanyaColors.terracottaNuitLight,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AlanyaColors.craie2,
          );
        }),
      ),

      cardTheme: CardThemeData(
        color: darkSurfaceHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF272750), width: 0.5),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AlanyaColors.ligne,
        thickness: 0.5,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurfaceHigh,
        contentTextStyle: const TextStyle(
          color: AlanyaColors.craie,
          fontFamily: 'Inter',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: AlanyaColors.craie2,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AlanyaColors.craie2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF272750)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF272750)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.terracottaNuit, width: 1.5),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AlanyaColors.terracottaNuit,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );
  }

  /// Troisième thème : **Noir**. Base noire OLED, accent teal unique.
  ///
  /// Sa `brightness` est `dark`, et c'est délibéré : les 218 appels à
  /// `themed()`, `accentOf()` et `mutedOf()` répartis dans l'application
  /// branchent sur ce booléen. En restant « sombre », Noir hérite de tout
  /// l'existant sans qu'aucun de ces sites ne soit modifié — seules les
  /// valeurs changent, par la ThemeExtension et par ce ColorScheme.
  ///
  /// Différence de fond avec Nuit : Nuit a deux accents (terre cuite pour
  /// l'action, indigo pour l'identité), Noir n'en a qu'un. Le teal porte donc
  /// à la fois `primary` et `secondary`.
  static ThemeData get noir {
    const bg = AlanyaColors.noir;          // #000000
    const surface = AlanyaColors.noir2;    // #0D0D0D
    const surfaceHigh = AlanyaColors.noir3; // #1C1C1E

    final colorScheme = ColorScheme.dark(
      primary: AlanyaColors.teal,
      onPrimary: Colors.white,
      primaryContainer: AlanyaColors.tealSombre,
      onPrimaryContainer: AlanyaColors.noirTexte,
      // Un seul accent : secondary reprend le teal plutôt que d'introduire une
      // seconde couleur que le modèle ne prévoit pas.
      secondary: AlanyaColors.teal,
      onSecondary: Colors.white,
      secondaryContainer: AlanyaColors.tealSombre,
      onSecondaryContainer: AlanyaColors.noirTexte,
      tertiary: AlanyaColors.teal,
      onTertiary: AlanyaColors.noir,
      surface: surface,
      onSurface: AlanyaColors.noirTexte,
      onSurfaceVariant: AlanyaColors.noirTexte2,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceHigh,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: const Color(0xFF2C2C2E),
      outline: AlanyaColors.noirLigne,
      outlineVariant: AlanyaColors.noirLigne,
      error: AlanyaColors.erreurNoir,
      onError: Colors.black,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      textTheme: _buildTextTheme(
        Brightness.dark,
        corps: AlanyaColors.noirTexte,
        attenue: AlanyaColors.noirTexte2,
      ),
      extensions: const [AlanyaSurfaces.noir],

      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: AlanyaColors.noirTexte,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.noirTexte,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AlanyaColors.teal.withValues(alpha: 0.22),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AlanyaColors.teal, size: 24);
          }
          return const IconThemeData(color: AlanyaColors.noirTexte2, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AlanyaColors.teal,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AlanyaColors.noirTexte2,
          );
        }),
      ),

      cardTheme: CardThemeData(
        color: surfaceHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AlanyaColors.noirLigne, width: 0.5),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AlanyaColors.noirLigne,
        thickness: 0.5,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(
          color: AlanyaColors.noirTexte,
          fontFamily: 'Inter',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: AlanyaColors.noirTexte2,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AlanyaColors.noirChamp,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AlanyaColors.noirTexte2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.noirLigne),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.noirLigne),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.teal, width: 1.5),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AlanyaColors.teal,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TYPOGRAPHY (Inter)
  // ---------------------------------------------------------------------------
  /// [corps] et [attenue] ne servent qu'au thème Noir, dont le texte est blanc
  /// franc et non le craie chaud de Nuit. Sans argument, le comportement
  /// d'origine est strictement conservé pour Clair et Nuit.
  static TextTheme _buildTextTheme(Brightness brightness,
      {Color? corps, Color? attenue}) {
    final Color bodyColor = corps ??
        (brightness == Brightness.light
            ? AlanyaColors.ink
            : AlanyaColors.craie);
    final Color mutedColor = attenue ??
        (brightness == Brightness.light
            ? AlanyaColors.grey500
            : AlanyaColors.craie2);

    return TextTheme(
      // Display
      displayLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: bodyColor,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        letterSpacing: -0.5,
        height: 1.25,
      ),

      // Headline
      headlineLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        letterSpacing: -0.3,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: -0.1,
        height: 1.35,
      ),

      // Title
      titleLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0,
        height: 1.4,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.1,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: bodyColor,
        letterSpacing: 0.1,
        height: 1.4,
      ),

      // Body
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: mutedColor,
        letterSpacing: 0.2,
        height: 1.5,
      ),

      // Label
      labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.3,
        height: 1.4,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: bodyColor,
        letterSpacing: 0.4,
        height: 1.4,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: mutedColor,
        letterSpacing: 0.5,
        height: 1.4,
      ),
    );
  }
}
