import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/theme/app_colors.dart';

class HomeShellPage extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const HomeShellPage({super.key, required this.navigationShell});

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.groups_rounded, 'Team'),
    (Icons.leaderboard_rounded, 'Ranks'),
    (Icons.sports_soccer_rounded, 'Matches'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.10);

    return Scaffold(
      // Render the shell directly — StatefulShellRoute keeps each branch alive,
      // so switching tabs is instant. (A crossfade here rebuilt the whole
      // branch every switch and felt laggy.)
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navColor,
          border: Border(top: BorderSide(color: border)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _items.length; i++)
                  _NavItem(
                    icon: _items[i].$1,
                    label: _items[i].$2,
                    selected: navigationShell.currentIndex == i,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      navigationShell.goBranch(
                        i,
                        initialLocation: i == navigationShell.currentIndex,
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = AppColors.iconAccent(context);
    final color = selected ? accent : onSurface.withValues(alpha: 0.6);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Thin top indicator marks the active tab — restrained, no fill.
            Container(
              width: 22,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 9),
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
