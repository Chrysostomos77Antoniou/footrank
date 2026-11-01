import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/pages/admin_courts_page.dart';
import 'package:footrank/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:footrank/admin/presentation/pages/admin_flagged_page.dart';
import 'package:footrank/admin/presentation/pages/admin_login_page.dart';
import 'package:footrank/admin/presentation/pages/admin_matches_page.dart';
import 'package:footrank/admin/presentation/pages/admin_teams_page.dart';
import 'package:footrank/admin/presentation/pages/admin_users_page.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/services/supabase_service.dart';

/// Public (not file-private) so [AdminDashboardPage]'s shortcut cards can
/// target a section by name without the shell needing to know anything
/// about dashboard internals -- it just receives an [AdminSection] back.
enum AdminSection { dashboard, courts, matches, flagged, teams, users }

const _phoneBreakpoint = 700.0;

const _sections = [
  (AdminSection.dashboard, Icons.dashboard_outlined, 'Dashboard'),
  (AdminSection.courts, Icons.place_outlined, 'Courts'),
  (AdminSection.matches, Icons.sports_soccer_outlined, 'Matches'),
  (AdminSection.flagged, Icons.flag_outlined, 'Flagged'),
  (AdminSection.teams, Icons.shield_outlined, 'Teams'),
  (AdminSection.users, Icons.people_outline, 'Users'),
];

class AdminShell extends StatefulWidget {
  /// Test/preview hooks: a stand-in repository and a bypass for the sign-in
  /// check. Production uses neither.
  final AdminRepository? repo;
  final bool skipAuth;

  const AdminShell({super.key, this.repo, this.skipAuth = false});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late final AdminRepository _adminRepo = widget.repo ?? AdminRepository();

  // null = still checking; false = show login; true = show the panel.
  bool? _authorized;
  AdminSection _section = AdminSection.dashboard;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    if (widget.skipAuth) {
      setState(() => _authorized = true);
      return;
    }
    final hasSession = SupabaseService.client.auth.currentUser != null;
    if (!hasSession) {
      setState(() => _authorized = false);
      return;
    }
    final isAdmin = await _adminRepo.isCurrentUserAdmin();
    if (!isAdmin) await SupabaseService.client.auth.signOut();
    if (mounted) setState(() => _authorized = isAdmin);
  }

  Future<void> _signOut() async {
    await SupabaseService.client.auth.signOut();
    if (mounted) setState(() => _authorized = false);
  }

  Widget get _content => IndexedStack(
    // Loose (the default) lets each child's own layout decide the
    // Stack's size, which can starve a Row+Expanded header down to a
    // sliver during that negotiation. Expand gives every child the
    // same tight, full-size constraint up front.
    sizing: StackFit.expand,
    index: AdminSection.values.indexOf(_section),
    children: [
      AdminDashboardPage(
        onNavigate: (s) => setState(() => _section = s),
        repo: widget.repo,
      ),
      AdminCourtsPage(repo: widget.repo),
      AdminMatchesPage(repo: widget.repo),
      AdminFlaggedPage(repo: widget.repo),
      AdminTeamsPage(repo: widget.repo),
      AdminUsersPage(repo: widget.repo),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_authorized == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: AmbientBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_authorized == false) {
      return AdminLoginPage(
        onSignedIn: () => setState(() => _authorized = true),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < _phoneBreakpoint;
        return isPhone
            ? _PhoneLayout(
                section: _section,
                onSelect: (s) => setState(() => _section = s),
                onSignOut: _signOut,
                content: _content,
              )
            : _DesktopLayout(
                section: _section,
                onSelect: (s) => setState(() => _section = s),
                onSignOut: _signOut,
                content: _content,
              );
      },
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;
  final Widget content;

  const _DesktopLayout({
    required this.section,
    required this.onSelect,
    required this.onSignOut,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: Row(
          children: [
            _Sidebar(
              section: section,
              onSelect: onSelect,
              onSignOut: onSignOut,
            ),
            Expanded(
              child: SafeArea(
                left: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneLayout extends StatelessWidget {
  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;
  final Widget content;

  const _PhoneLayout({
    required this.section,
    required this.onSelect,
    required this.onSignOut,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const AdminLogo(size: 30),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: GradientText(
                        'FootRank Admin',
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(Icons.logout, size: 20),
                      onPressed: onSignOut,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _PhoneNavBar(section: section, onSelect: onSelect),
    );
  }
}

/// Bottom tab bar for phones. One pill slides under the active tab (the same
/// idea as the desktop sidebar) and each tab presses in on touch.
class _PhoneNavBar extends StatelessWidget {
  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;

  const _PhoneNavBar({required this.section, required this.onSelect});

  static const _barHeight = 62.0;
  static const _pillW = 58.0;
  static const _pillH = 30.0;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brand(context);
    final hint = Theme.of(context).hintColor;
    final index = AdminSection.values.indexOf(section);
    final reduce = reduceMotion(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkNav : AppColors.lightCard,
        border: Border(top: BorderSide(color: AppColors.border(context))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: LayoutBuilder(
            builder: (context, c) {
              final itemW = c.maxWidth / _sections.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: kAdminEaseInOut,
                    left: index * itemW + (itemW - _pillW) / 2,
                    top: 8,
                    width: _pillW,
                    height: _pillH,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(_pillH / 2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final (i, s) in _sections.indexed)
                        Expanded(
                          child: _PhoneNavItem(
                            icon: s.$2,
                            label: s.$3,
                            selected: i == index,
                            accent: accent,
                            hint: hint,
                            onTap: () => onSelect(s.$1),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PhoneNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final Color hint;
  final VoidCallback onTap;

  const _PhoneNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : hint;
    return AdminPressScale(
      scale: 0.92,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            children: [
              const SizedBox(height: 8),
              SizedBox(
                height: _PhoneNavBar._pillH,
                child: Center(
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: color),
                    duration: const Duration(milliseconds: 180),
                    builder: (context, c, _) => Icon(icon, size: 22, color: c),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;

  const _Sidebar({
    required this.section,
    required this.onSelect,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: Border(right: BorderSide(color: AppColors.border(context))),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  const AdminLogo(size: 34),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: GradientText(
                      'FootRank',
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg + 42),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Admin',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).hintColor,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _NavList(section: section, onSelect: onSelect),
            const Spacer(),
            const _SignedInChip(),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: SizedBox(
                height: _NavList.itemHeight,
                child: _NavItem(
                  icon: Icons.logout,
                  label: 'Sign out',
                  selected: false,
                  onTap: onSignOut,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who is signed in, with a live dot -- a quiet confirmation you're in the
/// right account before touching production data.
class _SignedInChip extends StatelessWidget {
  const _SignedInChip();

  @override
  Widget build(BuildContext context) {
    String? email;
    try {
      email = SupabaseService.client.auth.currentUser?.email;
    } catch (_) {}
    if (email == null) return const SizedBox.shrink();
    final hint = Theme.of(context).hintColor;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          const PulseDot(color: AppColors.success, size: 7),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: hint, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sidebar's section list. A single highlight pill slides between
/// items (instead of each item fading its own background in and out), so
/// the selection reads as one object moving -- ease-in-out, because it
/// travels while staying on screen.
class _NavList extends StatelessWidget {
  static const itemHeight = 44.0;
  static const _gap = 4.0;

  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;

  const _NavList({required this.section, required this.onSelect});

  double _top(int i) => i * (itemHeight + _gap);

  @override
  Widget build(BuildContext context) {
    final index = AdminSection.values.indexOf(section);
    final accent = AppColors.brand(context);
    return SizedBox(
      width: double.infinity,
      height: _sections.length * (itemHeight + _gap),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: kAdminEaseInOut,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            top: _top(index),
            height: itemHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
          for (var i = 0; i < _sections.length; i++)
            Positioned(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              top: _top(i),
              height: itemHeight,
              child: _NavItem(
                icon: _sections[i].$2,
                label: _sections[i].$3,
                selected: i == index,
                onTap: () => onSelect(_sections[i].$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
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
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brand(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final base = Theme.of(context).hintColor;
    final color = widget.selected
        ? accent
        : (_hover || _focus)
        ? onSurface
        : base;
    final dur = reduceMotion(context) ? Duration.zero : kAdminHover;

    return AdminPressScale(
      scale: 0.98,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          selected: widget.selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.ease,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                // The sliding pill paints the selected state; this is only
                // the hover wash on the others.
                color: (!widget.selected && (_hover || _focus))
                    ? onSurface.withValues(alpha: 0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: dur,
                curve: Curves.ease,
                builder: (context, c, _) => Row(
                  children: [
                    Icon(widget.icon, size: 20, color: c),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      widget.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: c,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
