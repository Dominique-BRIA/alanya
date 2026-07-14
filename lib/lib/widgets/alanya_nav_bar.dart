import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// NavigationBar premium pour Alanya.
///
/// Design : indicateur arrondi animé, icônes fines, labels discrets,
/// fond transparent avec effet de flou léger.
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
    final bgColor = isDark
        ? const Color(0xFF121010).withValues(alpha: 0.95)
        : AlanyaColors.warmWhite.withValues(alpha: 0.95);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : AlanyaColors.grey200,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              return _NavTile(
                item: items[i],
                isSelected: i == currentIndex,
                onTap: () => onTap(i),
                isDark: isDark,
              );
            }),
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
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final activeColor = AlanyaColors.terracotta;
    final inactiveColor = isDark
        ? AlanyaColors.grey500
        : AlanyaColors.grey400;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                key: ValueKey(isSelected),
                size: 24,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
                letterSpacing: 0.2,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
