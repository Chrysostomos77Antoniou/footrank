import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';

class HomeShellPage extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const HomeShellPage({super.key, required this.navigationShell});

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage>
    with SingleTickerProviderStateMixin {
  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.groups_rounded, 'Team'),
    (Icons.leaderboard_rounded, 'Ranks'),
    (Icons.sports_soccer_rounded, 'Matches'),
    (Icons.person_rounded, 'Profile'),
  ];

  // Purely a paint-time fade+slide overlay on the *same* navigationShell
  // instance -- it never rebuilds or re-keys that widget, so every branch
  // stays alive exactly as before (a full crossfade here was tried once and
  // felt laggy because it rebuilt the branch on every switch; this doesn't).
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..value = 1;
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  Animation<Offset> _slide = const AlwaysStoppedAnimation(Offset.zero);

  @override
  void didUpdateWidget(covariant HomeShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = oldWidget.navigationShell.currentIndex;
    final newIndex = widget.navigationShell.currentIndex;
    if (oldIndex != newIndex) {
      final forward = newIndex > oldIndex;
      _slide = Tween<Offset>(
        begin: Offset(forward ? 0.05 : -0.05, 0),
        end: Offset.zero,
      ).animate(_fade);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    HapticFeedback.selectionClick();
    widget.navigationShell.goBranch(index);
    triggerUiRepaint();
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    // Fixed brand green in both themes (not the lime-in-dark-mode accent
    // used elsewhere) -- this bar is meant to read as solid green always.
    return Scaffold(
      // A horizontal swipe here moves to the adjacent tab -- separate from
      // (and never conflicting with) the swipe-to-go-back gesture on pushed
      // pages, since a pushed page fully covers this shell while it's open.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.velocity.pixelsPerSecond.dx;
          final current = navigationShell.currentIndex;
          if (v < -300 && current < _items.length - 1) {
            _goToTab(current + 1);
          } else if (v > 300 && current > 0) {
            _goToTab(current - 1);
          }
        },
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: navigationShell,
          ),
        ),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.limeDeep, AppColors.limeDeeper],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, -4),
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
                        // Repaint the now-visible tab's UI (no data re-fetch).
                        triggerUiRepaint();
                      },
                    ),
                ],
              ),
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
    // White on the fixed green bar, not the theme-flipping accent color —
    // this bar is solid green in both themes now, so its content needs to
    // contrast against green specifically, not the page's own accent.
    final color = selected ? Colors.white : Colors.white.withValues(alpha: 0.65);
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
                color: selected ? Colors.white : Colors.transparent,
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
