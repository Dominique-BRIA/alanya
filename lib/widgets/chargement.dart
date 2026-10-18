import 'package:flutter/material.dart';

import '../theme/alanya_theme.dart';

/// Les deux visages d'un écran qui charge (demande du user, 18/10/2026).
///
/// * **Squelette** ([SqueletteListe]) : au TOUT PREMIER affichage, ou quand
///   le téléphone n'a encore rien gardé pour cet écran. Des blocs à la forme
///   du contenu, plutôt qu'une roue qui tourne au milieu du vide.
/// * **Fine barre** ([BarreMiseAJour]) : l'écran montre déjà la dernière
///   version gardée sur le téléphone, et la version à jour arrive du serveur.
///   Elle la remplace sur place, sans toucher au défilement ni à la saisie.
///
/// ⚠️ JAMAIS LES DEUX À LA FOIS, ET JAMAIS DE ROUE DEVANT UNE COPIE : dès
/// qu'un écran a quelque chose à montrer, il le montre.

/// Une liste « fantôme » : un rond (avatar) et deux lignes par rangée, qui
/// pulsent doucement. Immobile si le téléphone demande de réduire les
/// animations.
class SqueletteListe extends StatefulWidget {
  const SqueletteListe({super.key, this.lignes = 8, this.avatar = true});

  final int lignes;

  /// Faux pour une liste sans photo (réunions, entreprises…).
  final bool avatar;

  @override
  State<SqueletteListe> createState() => _SqueletteListeState();
}

class _SqueletteListeState extends State<SqueletteListe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulsation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulsation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = themed(context,
        light: const Color(0x14000000), dark: const Color(0x1FFFFFFF));
    Widget bloc(double hauteur, {double? largeur, bool rond = false}) =>
        Container(
          height: hauteur,
          width: largeur ?? (rond ? hauteur : null),
          decoration: BoxDecoration(
            color: couleur,
            shape: rond ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: rond ? null : BorderRadius.circular(6),
          ),
        );

    final liste = ListView.builder(
      // Un squelette ne se fait pas défiler : il tient la place, c'est tout.
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.lignes,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          if (widget.avatar) ...[bloc(44, rond: true), const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Des largeurs qui varient : une colonne de barres identiques
                // se lit comme un motif, pas comme une liste.
                FractionallySizedBox(
                    widthFactor: 0.75 - (i % 3) * 0.15, child: bloc(13)),
                const SizedBox(height: 8),
                FractionallySizedBox(
                    widthFactor: 0.45 + (i % 2) * 0.2, child: bloc(10)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          bloc(10, largeur: 32),
        ]),
      ),
    );

    final animer = !MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'Chargement',
      liveRegion: true,
      child: ExcludeSemantics(
        child: animer
            ? FadeTransition(
                opacity: Tween(begin: 1.0, end: 0.45).animate(_pulsation),
                child: liste,
              )
            : liste,
      ),
    );
  }
}

/// La fine barre en haut d'un écran pendant que la version à jour arrive.
///
/// Elle garde sa place (2 points) même éteinte : son apparition ne doit pas
/// pousser le contenu d'un cran — ce serait justement le saut qu'on évite.
class BarreMiseAJour extends StatelessWidget {
  const BarreMiseAJour({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: visible
            ? LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: accentOf(context),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Le squelette d'une discussion : des bulles, à gauche et à droite.
///
/// Au premier affichage d'un fil que ce téléphone n'a jamais gardé — dès qu'une
/// copie existe, elle s'affiche à sa place.
class SqueletteDiscussion extends StatefulWidget {
  const SqueletteDiscussion({super.key});

  @override
  State<SqueletteDiscussion> createState() => _SqueletteDiscussionState();
}

class _SqueletteDiscussionState extends State<SqueletteDiscussion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulsation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulsation.dispose();
    super.dispose();
  }

  // Largeur (fraction de l'écran), hauteur, côté : un fil plausible.
  static const _bulles = [
    (0.55, 38.0, false),
    (0.40, 38.0, false),
    (0.62, 56.0, true),
    (0.35, 38.0, true),
    (0.70, 74.0, false),
    (0.48, 38.0, true),
    (0.58, 56.0, false),
    (0.30, 38.0, true),
  ];

  @override
  Widget build(BuildContext context) {
    final couleur = themed(context,
        light: const Color(0x14000000), dark: const Color(0x1FFFFFFF));
    final liste = ListView(
      // Ancré en bas, comme le vrai fil : le squelette ne « tombe » pas
      // quand les messages arrivent.
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        for (final (largeur, hauteur, moi) in _bulles)
          Align(
            alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: largeur,
              child: Container(
                height: hauteur,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: couleur,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
      ],
    );
    final animer = !MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'Chargement',
      liveRegion: true,
      child: ExcludeSemantics(
        child: animer
            ? FadeTransition(
                opacity: Tween(begin: 1.0, end: 0.45).animate(_pulsation),
                child: liste,
              )
            : liste,
      ),
    );
  }
}
