import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/alanya_theme.dart';
import '../call_controller.dart';

/// Pavé numérique d'un standard téléphonique, affiché DANS l'écran d'appel.
///
/// ```
/// menu ──(appui)──► envoi ──(ivr_hold)──► attente ──(décrochage)──► appel
///   ▲                 │
///   └──(erreur avec retour possible)──┘
/// ```
///
/// L'état « appel » n'apparaît pas ici : quand l'agent décroche, la session
/// disparaît du contrôleur et ce panneau avec elle. L'écran qui le portait était
/// déjà affiché — il n'y a rien à ouvrir, rien à préparer.
///
/// ⚠️ POURQUOI UN PAVÉ ET NON LA LISTE DES SERVICES.
///
/// La première version affichait les options en liste. C'était plus lisible,
/// mais cela liait la FORME de l'écran au CONTENU du menu : un standard à
/// sous-menus, une invite qui demanderait un numéro de dossier, ou simplement un
/// menu plus long, auraient demandé de retoucher le client — donc un nouvel APK
/// à chaque évolution d'un vocal. Un pavé numérique, lui, ne dépend de rien : il
/// a les mêmes dix touches quel que soit le standard appelé, aujourd'hui et
/// demain.
///
/// Le libellé n'est pas perdu pour autant : **maintenir une touche l'affiche**,
/// juste au-dessus du pavé. On garde donc l'avantage de l'écran — savoir ce que
/// fait une touche sans avoir à retenir l'annonce vocale — sans en payer le prix
/// en rigidité.
class IvrPanel extends StatefulWidget {
  const IvrPanel({
    super.key,
    required this.session,
    required this.onTouche,
    required this.onRetourAccueil,
  });

  final IvrSession session;
  final Future<void> Function(int digit) onTouche;

  /// « Retour à l'accueil » d'un centre vocal. Jamais appelé pour un centre
  /// d'appels : le bouton n'y est pas affiché.
  final Future<void> Function() onRetourAccueil;

  /// Ce panneau montre-t-il le PAVÉ, ou l'écran d'attente ?
  ///
  /// 🔴 **UN SEUL ENDROIT RÉPOND À CETTE QUESTION**, et c'est tout l'intérêt de
  /// cette fonction. L'écran d'appel a besoin de la même réponse que [build] :
  /// c'est elle qui décide s'il doit rendre son en-tête compact pour laisser la
  /// place aux touches. Tant qu'il la redemandait à sa façon — en testant
  /// `etape == menu` —, l'ajout d'une étape suffisait à les faire diverger : le
  /// panneau affichait le pavé, l'écran croyait le contraire, et l'avatar
  /// reprenait sa grande taille au milieu d'une lecture (signalé par le user le
  /// 18/08/2026).
  ///
  /// La formulation par la NÉGATIVE n'est pas un détail : « le pavé est là sauf
  /// pendant l'attente » reste vraie pour toute étape qu'on ajouterait ensuite,
  /// alors qu'une liste d'étapes autorisées serait à compléter à chaque fois —
  /// et l'oubli ne casserait rien de visible ici, seulement la taille des
  /// touches là-bas.
  static bool afficheLePave(IvrSession session) =>
      session.etape != IvrEtape.attente;

  /// Repère de test posé sur le pavé — voir `test/ivr_panel_hauteur_test.dart`.
  ///
  /// La règle « le pavé ne change jamais de taille pendant un appel » s'est
  /// cassée DEUX FOIS (17/08 puis 18/08/2026), et à chaque fois parce qu'un
  /// élément situé AU-DESSUS de lui variait — jamais le pavé lui-même. Une
  /// relecture n'attrape pas ça : il faut mesurer. Cette clé est le seul moyen
  /// de le faire depuis un test.
  static const cleDuPave = Key("ivr-pave");

  @override
  State<IvrPanel> createState() => _IvrPanelState();
}

class _IvrPanelState extends State<IvrPanel> {
  /// Touche actuellement maintenue, dont le libellé est révélé. Nulle sinon.
  int? _maintenue;

  /// Battement du minuteur d'attente. Une seconde, et seulement pendant
  /// l'attente : rien ne tourne quand le pavé est affiché.
  Timer? _battement;

  @override
  void didUpdateWidget(IvrPanel ancien) {
    super.didUpdateWidget(ancien);
    _regleBattement();
  }

  @override
  void initState() {
    super.initState();
    _regleBattement();
  }

  @override
  void dispose() {
    _battement?.cancel();
    super.dispose();
  }

  /// Démarre ou arrête le battement selon l'étape.
  ///
  /// ⚠️ Le minuteur ne COMPTE pas : il ne fait que redemander un affichage. Le
  /// temps montré est toujours calculé depuis `attenteDepuis`, donc il reste
  /// juste même si l'application a été mise en veille — un compteur incrémenté
  /// à chaque battement, lui, aurait pris du retard.
  void _regleBattement() {
    final enAttente = widget.session.etape == IvrEtape.attente &&
        widget.session.attenteDepuis != null;
    if (enAttente && _battement == null) {
      _battement = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!enAttente) {
      _battement?.cancel();
      _battement = null;
    }
  }

  String _dureeAttente() {
    final debut = widget.session.attenteDepuis;
    if (debut == null) return "00:00";
    final s = DateTime.now().difference(debut).inSeconds;
    final m = s ~/ 60;
    return "${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";
  }

  IvrOption? _optionPour(int digit) {
    for (final o in widget.session.options) {
      if (o.digit == digit) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!IvrPanel.afficheLePave(widget.session)) return _attente();

    // 🔴 **LE MESSAGE N'EST PLUS AFFICHÉ ICI**, et c'est la correction du
    // rétrécissement du pavé signalé par le user (17/08/2026).
    //
    // Il était posé au-dessus du pavé, dans cette même colonne. Or le pavé est
    // le seul `Expanded` : il prend « ce qui reste ». Chaque apparition du
    // bandeau — typiquement au retour au menu après une attente sans réponse —
    // lui retirait donc sa hauteur, et le pavé revenait plus petit qu'il
    // n'était parti.
    //
    // Le message est désormais rendu par l'écran d'appel, dans une bande de
    // hauteur CONSTANTE placée entre l'avatar et le nom du centre. La hauteur
    // laissée au pavé ne dépend donc plus de la présence d'un message, sans
    // qu'aucune dimension du pavé n'ait été figée.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Hauteur FIXE : sans elle, le pavé sauterait d'une dizaine de pixels
        // à chaque appui long, et la touche glisserait sous le doigt.
        _revelation(),
        // ⚠️ MÊME RÈGLE QUE `_revelation` : hauteur CONSTANTE, occupée ou non.
        // Un bandeau qui apparaît en lecture reprendrait sinon sa hauteur au
        // pavé — c'est exactement le rétrécissement corrigé le 17/08/2026 —
        // et les touches changeraient de taille au premier appui.
        _bandeauLecture(),
        const SizedBox(height: 8),
        // `Expanded` et plus `Flexible` + `SingleChildScrollView` : le pavé
        // occupe exactement la place disponible au lieu de déborder. Voir
        // [_pave].
        Expanded(child: _pave()),
      ],
    );
  }

  // ── La bulle qui révèle le service d'une touche ──────────────────────────

  Widget _revelation() {
    final digit = _maintenue;
    final option = digit == null ? null : _optionPour(digit);

    String? titre;
    String? sous;
    if (digit != null) {
      if (option == null) {
        titre = "Aucun service sur cette touche";
      } else {
        // `nom_service` d'abord, `libelle` en repli — demande du user du
        // 12/08/2026. Les deux viennent de la table `center` : le premier est le
        // nom montré au public, le second le nom interne de la ligne.
        titre = option.nomAffiche;
        if (!option.disponible) sous = "Bientôt disponible";
      }
    }

    return SizedBox(
      height: 46,
      child: AnimatedOpacity(
        opacity: titre == null ? 0 : 1,
        duration: const Duration(milliseconds: 120),
        child: titre == null
            ? const SizedBox.shrink()
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sous != null)
                      Text(
                        sous,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Ce qui joue, et par où revenir (centre vocal seulement) ──────────────

  /// Bandeau de lecture d'un centre vocal : ce qui joue, et « Retour à
  /// l'accueil ».
  ///
  /// ⚠️ Le pavé reste ACTIF pendant la lecture — le user veut pouvoir passer
  /// d'un son à l'autre sans repasser par l'accueil. Ce bandeau n'est donc pas
  /// un écran de lecture qui remplacerait le pavé, mais une bande au-dessus de
  /// lui, exactement comme la révélation d'un appui long.
  ///
  /// Hauteur RÉSERVÉE au bandeau, et jamais reprise.
  ///
  /// 🔴 **NULLE POUR UN CENTRE D'APPELS.** Elle valait 40 pour tout le monde,
  /// donc mon bandeau prenait 40 points aux touches d'un standard qui ne peut
  /// jamais l'afficher — une régression sur un pavé que le user avait
  /// précisément fait ajuster au point près le 17/08/2026.
  ///
  /// ⚠️ Elle ne dépend que de `vocal`, qui est `final` et fixé à la création de
  /// la session : elle est donc CONSTANTE pendant toute la durée d'un appel. La
  /// faire dépendre de l'étape aurait ramené le défaut d'origine — le pavé
  /// rétrécissant au premier appui, puisqu'il prend « ce qui reste ».
  double get _hauteurBandeau => widget.session.vocal ? 40 : 0;

  Widget _bandeauLecture() {
    final s = widget.session;
    final enLecture = s.vocal && s.etape == IvrEtape.lecture;

    return SizedBox(
      height: _hauteurBandeau,
      child: AnimatedOpacity(
        opacity: enLecture ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: !enLecture
            ? const SizedBox.shrink()
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.graphic_eq, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  // `Flexible` + ellipse : un titre saisi depuis la plateforme
                  // n'a aucune longueur garantie, et un débordement ferait
                  // passer la ligne jaune et noire de Flutter par-dessus le
                  // pavé.
                  Flexible(
                    child: Text(
                      s.titreEnLecture ?? "Lecture en cours",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => widget.onRetourAccueil(),
                    icon: const Icon(Icons.home_outlined, size: 16),
                    label: const Text("Accueil"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Le pavé ──────────────────────────────────────────────────────────────

  /// Les quatre rangées du pavé. `null` = case vide, autour du zéro.
  static const List<List<int?>> _rangees = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
    [null, 0, null],
  ];

  /// Le pavé, qui TIENT TOUJOURS DANS LA HAUTEUR DISPONIBLE.
  ///
  /// 🐛 Il fallait tirer vers le bas pour atteindre le zéro (signalé par le user
  /// le 12/08/2026). La cause était un `GridView` à `childAspectRatio` FIXE
  /// (1.7) posé dans une zone scrollable : la hauteur des touches ne dépendait
  /// que de leur largeur, donc de celle de l'écran. Dès que la place verticale
  /// manquait — écran court, bandeau de message affiché, barre système haute —
  /// la quatrième rangée passait dessous, et un pavé numérique qu'il faut faire
  /// défiler pour trouver le zéro n'est plus un pavé numérique.
  ///
  /// Des rangées `Expanded` plutôt qu'un ratio calculé : la contrainte « remplir
  /// exactement la hauteur, quelle qu'elle soit » est ainsi tenue par la mise en
  /// page elle-même, sans arithmétique à refaire à chaque changement d'espacement
  /// ou de marge — et donc sans possibilité de la fausser d'un pixel.
  /// Marge horizontale, réduite de 44 à 20 le 12/08/2026.
  ///
  /// Les touches trouvaient leur hauteur dans la place laissée par l'en-tête, et
  /// paraissaient donc plus petites qu'avant une fois toutes visibles. Élargir
  /// est le seul levier qui les agrandit SANS reprendre de la hauteur : sur un
  /// écran de 360 points, une touche passe ainsi de 80 à 96 points de large.
  /// Marge horizontale portée de 20 à 30 le 17/08/2026 : c'est le levier qui
  /// réduit la taille des touches d'environ 5 %, comme demandé, **sans écrire
  /// aucune dimension de touche en dur** — elles continuent de se déduire de la
  /// place disponible, donc de s'adapter à tous les écrans.
  static const _margeH = 30.0;

  /// Air sous le zéro. 🐛 Le pavé touchait le bouton « Raccrocher », au point
  /// qu'un doigt visant le 0 risquait de raccrocher (signalé par le user le
  /// 17/08/2026). Cette marge est aussi ce qui retire les ~5 % de hauteur.
  static const _margeBas = 18.0;

  Widget _pave() {
    return Padding(
      key: IvrPanel.cleDuPave,
      padding: const EdgeInsets.fromLTRB(_margeH, 0, _margeH, _margeBas),
      child: Column(
        children: [
          for (var r = 0; r < _rangees.length; r++) ...[
            // Écarts resserrés (10 → 8 et 16 → 12) : les touches étant plus
            // petites, les mêmes espaces paraissaient béants entre elles.
            if (r > 0) const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < _rangees[r].length; c++) ...[
                    if (c > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _rangees[r][c] == null
                          ? const SizedBox.shrink()
                          : _touche(_rangees[r][c]!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _touche(int digit) {
    final option = _optionPour(digit);
    final maintenue = _maintenue == digit;
    final verrouille = widget.session.envoiEnCours;
    final enLecture = widget.session.vocal &&
        widget.session.etape == IvrEtape.lecture &&
        widget.session.toucheEnLecture == digit;

    // `GestureDetector` et non `InkWell` : il faut savoir quand l'appui long se
    // TERMINE pour refermer la bulle, et `InkWell` n'expose pas ce moment.
    // Empiler les deux ferait cohabiter deux détecteurs dans la même arène de
    // gestes, où l'appui long des deux se disputerait le doigt. Le retour visuel
    // n'est pas perdu : la touche s'éclaircit tant qu'elle est maintenue.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Verrouillé pendant l'envoi : sur un réseau lent l'utilisateur insiste,
      // et deux appuis feraient sonner deux agents pour une seule intention.
      // Le serveur tient la même garde ; celle-ci évite d'en arriver là.
      onTap: verrouille ? null : () => widget.onTouche(digit),
      // L'appui long RÉVÈLE, il n'envoie pas. Il reste disponible même pendant
      // un envoi : consulter ce que fait une touche n'a aucun effet de bord.
      onLongPressStart: (_) {
        HapticFeedback.selectionClick();
        setState(() => _maintenue = digit);
      },
      onLongPressEnd: (_) => setState(() => _maintenue = null),
      onLongPressCancel: () => setState(() => _maintenue = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: maintenue ? 0.26 : 0.12),
          borderRadius: BorderRadius.circular(16),
          // Repère des touches qui mènent quelque part (15/08/2026) : un anneau
          // AUTOUR du bouton plutôt qu'un point sous le chiffre — remplace
          // l'ancien indicateur, demandé plus visible. Toujours discret : il ne
          // dit pas QUOI, l'appui long le dit toujours.
          //
          // La touche EN LECTURE (centre vocal) reprend le même anneau dans la
          // couleur d'accent : le pavé restant actif pendant la lecture, c'est
          // le seul repère qui dise laquelle des dix on est en train d'écouter.
          border: enLecture
              ? Border.all(color: AlanyaColors.terracotta, width: 2.5)
              : option == null
                  ? null
                  : Border.all(
                      color: option.disponible
                          ? AlanyaColors.forest
                          : Colors.white38,
                      width: 2,
                    ),
        ),
        // ⚠️ LE CHIFFRE SUIT LA TAILLE DE SA CASE, il n'est plus figé à 26
        // points. Une taille fixe donnait des touches qui paraissent petites dès
        // que la case s'agrandit, et un débordement dès qu'elle rétrécit. Le
        // `FittedBox` ne sait que RÉDUIRE (`scaleDown`) : il protège du second
        // cas, jamais du premier — d'où le calcul.
        //
        // 42 % de la hauteur, borné à [22, 38] : en dessous ce n'est plus
        // lisible, au-dessus le chiffre mange sa touche.
        child: LayoutBuilder(
          builder: (context, contraintes) {
            final taille =
                (contraintes.maxHeight * 0.42).clamp(22.0, 38.0).toDouble();
            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$digit",
                      style: TextStyle(
                        color: verrouille ? Colors.white38 : Colors.white,
                        fontSize: taille,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Attente : l'agent sonne ──────────────────────────────────────────────

  Widget _attente() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            // Même bleu que la vague autour de l'avatar : pendant l'attente,
            // les deux éléments animés parlent de la même chose.
            valueColor: AlwaysStoppedAnimation(AlanyaColors.bleuAppel),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          widget.session.serviceChoisi ?? "Mise en relation",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        // ⏱️ Minuteur d'attente (demande du user, 17/08/2026).
        //
        // Mesuré sur device : 95 secondes entre le choix du service et le
        // « n'a pas répondu », sans le moindre repère à l'écran. La durée est
        // recalculée depuis `attenteDepuis` à chaque battement — c'est du temps
        // réellement écoulé, pas un compteur qui s'incrémente.
        if (widget.session.attenteDepuis != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule,
                  size: 14, color: AlanyaColors.bleuAppel),
              const SizedBox(width: 6),
              Text(
                _dureeAttente(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  // Chiffres à chasse fixe : sans cela « 01:09 » puis « 01:10 »
                  // font sauter le libellé d'un pixel à chaque seconde.
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        const Text(
          "Nous vous mettons en relation.\nMerci de patienter.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
}

/// Bande de message du standard, à hauteur CONSTANTE.
///
/// 🐛 **Contraste corrigé (17/08/2026)** : le message « … n'a pas répondu »
/// s'affichait en `orangeAccent` PLEIN sur un fond `orangeAccent` à 15 % — la
/// même couleur pour le texte et son fond, donc illisible. Il est désormais
/// blanc sur un fond sombre, avec un liseré orange qui conserve la valeur
/// d'alerte sans la porter à lui seul.
///
/// **Règle générale à reconduire** : un texte et son fond ne se distinguent
/// jamais par l'opacité d'une même teinte. La couleur d'alerte va au liseré ou
/// à l'icône ; le texte reste blanc.
///
/// ⚠️ **La hauteur ne dépend PAS de la présence d'un message** : c'est ce qui
/// garantit que le pavé numérique garde exactement la même taille dans tous les
/// états. Sans message, la bande est simplement vide.
class IvrMessageBand extends StatelessWidget {
  const IvrMessageBand({super.key, required this.message});

  final String? message;

  /// Au plus juste : deux lignes de texte à 13 points (~17 chacune) plus le
  /// rembourrage vertical, soit 52. Réduite au minimum parce que **cette bande
  /// est prise sur la hauteur du pavé numérique** : chaque point réservé ici est
  /// un point que les touches n'ont plus. Le cas le plus long observé en
  /// production — « Assistance technique n'a pas répondu » — tient en deux
  /// lignes sur un écran de 360 points.
  static const double hauteur = 52;

  @override
  Widget build(BuildContext context) {
    final texte = message;
    return SizedBox(
      height: hauteur,
      child: texte == null
          ? const SizedBox.shrink()
          : Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.85),
                      width: 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      texte,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
