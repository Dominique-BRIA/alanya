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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          // Modèle Nuit : barre d'onglets en nuit-2, cernée d'un filet indigo.
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: isDark ? Border.all(color: cs.outlineVariant, width: 0.5) : null,
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
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
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
    final cs = Theme.of(context).colorScheme;
    final activeColor = widget.isDark
        ? AlanyaColors.terracottaNuitLight
        : AlanyaColors.terracotta;
    final inactiveColor = cs.onSurfaceVariant;
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  widget.isSelected ? widget.item.activeIcon : widget.item.icon,
                  key: ValueKey(widget.isSelected),
                  size: 22,
                  color: widget.isSelected ? activeColor : inactiveColor,
                ),
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
