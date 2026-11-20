import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// NavigationBar flottante style Telegram — arrondie, avec indicateur animé.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          // Nuit : barre d'onglets en nuit-2, cernée d'un filet indigo.
          color: themed(context, light: Colors.white, dark: surfacesOf(context).surface),
          borderRadius: BorderRadius.circular(20),
          border:
              isDark ? Border.all(color: AlanyaColors.ligne, width: 0.5) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
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
