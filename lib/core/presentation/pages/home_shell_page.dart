import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  final _boundaryKey = GlobalKey();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  // A snapshot of whichever tab was on screen right before this switch, so
  // it can slide fully away while the new tab (already live underneath)
  // slides in from the other side -- both visible at once, like Instagram's
  // own tab switch, instead of just fading the destination in alone.
  ui.Image? _outgoingSnapshot;
  bool _forward = true;
  int _generation = 0;

  @override
  void dispose() {
    _controller.dispose();
    _outgoingSnapshot?.dispose();
    super.dispose();
  }

  Future<void> _switchTab(int newIndex, {bool tapSameTab = false}) async {
    final oldIndex = widget.navigationShell.currentIndex;
    if (newIndex == oldIndex) {
      if (tapSameTab) {
        HapticFeedback.selectionClick();
        widget.navigationShell.goBranch(newIndex, initialLocation: true);
        triggerUiRepaint();
      }
      return;
    }

    final myGeneration = ++_generation;
    ui.Image? snapshot;
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      snapshot = await boundary?.toImage(
        pixelRatio: MediaQuery.of(context).devicePixelRatio,
      );
    } catch (_) {
      snapshot = null; // fall back to a plain cut if capture fails
    }
    if (!mounted || myGeneration != _generation) {
      snapshot?.dispose();
      return;
    }

    HapticFeedback.selectionClick();
    widget.navigationShell.goBranch(newIndex);
    triggerUiRepaint();

    final oldSnapshot = _outgoingSnapshot;
    setState(() {
      _outgoingSnapshot = snapshot;
      _forward = newIndex > oldIndex;
    });
    oldSnapshot?.dispose();

    await _controller.forward(from: 0);
    if (!mounted || myGeneration != _generation) return;
    setState(() {
      _outgoingSnapshot?.dispose();
      _outgoingSnapshot = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final width = MediaQuery.of(context).size.width;
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
            _switchTab(current + 1);
          } else if (v > 300 && current > 0) {
            _switchTab(current - 1);
          }
        },
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, child) {
            final incomingX =
                _outgoingSnapshot == null ? 0.0 : (_forward ? 1 - _t.value : -(1 - _t.value)) * width;
            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  key: _boundaryKey,
                  child: Transform.translate(
                    offset: Offset(incomingX, 0),
                    child: navigationShell,
                  ),
                ),
                if (_outgoingSnapshot != null)
                  Transform.translate(
                    offset: Offset(
                      (_forward ? -_t.value : _t.value) * width,
                      0,
                    ),
                    child: SizedBox.expand(
                      child: RawImage(
                        image: _outgoingSnapshot,
                        fit: BoxFit.cover,
                        alignment: Alignment.topLeft,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: Builder(builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkNav : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : AppColors.ink.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _NavItem(
                      icon: _items[i].$1,
                      label: _items[i].$2,
                      selected: navigationShell.currentIndex == i,
                      onTap: () => _switchTab(i, tapSameTab: true),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppColors.muted(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    final pillColor = selected
        ? (isDark ? AppColors.lime.withValues(alpha: 0.16) : AppColors.lime)
        : Colors.transparent;
    final iconColor =
        selected ? (isDark ? AppColors.lime : AppColors.ink) : muted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 56,
                  height: 30,
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? ink : muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
