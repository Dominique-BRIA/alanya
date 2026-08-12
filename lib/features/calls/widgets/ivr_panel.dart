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
  });

  final IvrSession session;
  final Future<void> Function(int digit) onTouche;

  @override
  State<IvrPanel> createState() => _IvrPanelState();
}

class _IvrPanelState extends State<IvrPanel> {
  /// Touche actuellement maintenue, dont le libellé est révélé. Nulle sinon.
  int? _maintenue;

  IvrOption? _optionPour(int digit) {
    for (final o in widget.session.options) {
      if (o.digit == digit) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.etape == IvrEtape.attente) return _attente();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.session.message != null) ...[
          _bandeauMessage(widget.session.message!),
          const SizedBox(height: 12),
        ],
        // Hauteur FIXE : sans elle, le pavé sauterait d'une dizaine de pixels
        // à chaque appui long, et la touche glisserait sous le doigt.
        _revelation(),
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
  static const _margeH = 20.0;

  Widget _pave() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _margeH),
      child: Column(
        children: [
          for (var r = 0; r < _rangees.length; r++) ...[
            if (r > 0) const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < _rangees[r].length; c++) ...[
                    if (c > 0) const SizedBox(width: 16),
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
                    // Repère discret sur les touches qui mènent quelque part. Il
                    // ne dit PAS quoi — c'est l'appui long qui le dit — mais il
                    // évite de maintenir les dix touches une à une pour trouver
                    // les trois qui servent.
                    if (option != null)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: option.disponible
                              ? AlanyaColors.forest
                              : Colors.white38,
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
            valueColor: AlwaysStoppedAnimation(AlanyaColors.forest),
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
        const SizedBox(height: 8),
        const Text(
          "Nous vous mettons en relation.\nMerci de patienter.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }

  Widget _bandeauMessage(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
      ),
    );
  }
}
