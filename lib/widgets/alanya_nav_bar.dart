import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// NavigationBar flottante style Telegram — arrondie, avec indicateur animé.
///
/// ELLE PLANE (20/11/2026, demande du user, à l'identique sur le web) : fond
/// translucide et flouté, la liste défile DESSOUS et se voit à travers et à
/// côté d'elle. Le Scaffold de l'accueil passe donc `extendBody: true` : le
/// contenu descend jusqu'en bas de l'écran au lieu de s'arrêter au-dessus de
/// la barre, et les listes reçoivent la hauteur de la barre en marge basse
/// par le MediaQuery, pour que leur dernier élément reste atteignable.
class AlanyaNavBar extends StatelessWidget {
  const AlanyaNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AlanyaNavItem> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fond =
        themed(context, light: Colors.white, dark: surfacesOf(context).surface);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      // SafeArea en bas seulement : la barre reste au-dessus de la barre de
      // gestes, puisque le contenu passe désormais derrière elle.
      child: SafeArea(
        top: false,
        child: DecoratedBox(
        // L'ombre reste HORS du flou : posée sur la même boîte que le fond
        // translucide, elle se verrait à travers et le salirait.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
        height: 64,
        decoration: BoxDecoration(
          // Translucide : 62 % de la surface du thème, le reste laisse voir
          // la liste floutée. Nuit : nuit-2, cernée d'un filet indigo.
          color: fond.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AlanyaColors.ligne
                : Colors.white.withValues(alpha: 0.7),
            width: isDark ? 0.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(items.length, (i) {
            return Expanded(
              child: _NavTile(
                item: items[i],
                isSelected: i == currentIndex,
                onTap: () => onTap(i),
                isDark: isDark,
              ),
            );
          }),
        ),
        ),
        ),
        ),
        ),
      ),
    );
  }
}

class AlanyaNavItem {
  const AlanyaNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Nombre affiché dans la pastille. Zéro = aucune pastille.
  final int badge;
}

/// Pastille rouge de comptage, façon WhatsApp.
///
/// Rouge franc dans les quatre thèmes : c'est une alerte, pas un accent, et
/// elle doit se lire pareil partout. Au-delà de 99 elle affiche « 99+ », sans
/// quoi un nombre à quatre chiffres déformerait la barre.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.nombre});
  final int nombre;

  @override
  Widget build(BuildContext context) {
    final texte = nombre > 99 ? "99+" : "$nombre";
    return Container(
      padding: EdgeInsets.symmetric(horizontal: nombre > 9 ? 5 : 0),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(9),
        // Liseré de la couleur de la barre : détache la pastille de l'icône
        // quand elle la chevauche.
        border: Border.all(
          color: themed(context,
              light: Colors.white, dark: surfacesOf(context).surface),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        texte,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  final AlanyaNavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isDark
        ? AlanyaColors.terracottaNuitLight
        : AlanyaColors.terracotta;
    final inactiveColor =
        widget.isDark ? AlanyaColors.craie2 : AlanyaColors.grey400;
    final hoverColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.04)
        : AlanyaColors.grey100;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? activeColor.withValues(alpha: 0.12)
                : _hovering
                    ? hoverColor
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Stack en Clip.none : la pastille déborde sur le coin de
              // l'icône sans élargir la case, donc sans décaler les onglets
              // voisins quand elle apparaît.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      widget.isSelected
                          ? widget.item.activeIcon
                          : widget.item.icon,
                      key: ValueKey(widget.isSelected),
                      size: 22,
                      color: widget.isSelected ? activeColor : inactiveColor,
                    ),
                  ),
                  if (widget.item.badge > 0)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: _Pastille(nombre: widget.item.badge),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.isSelected ? activeColor : inactiveColor,
                  letterSpacing: 0.2,
                ),
                child: Text(widget.item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
