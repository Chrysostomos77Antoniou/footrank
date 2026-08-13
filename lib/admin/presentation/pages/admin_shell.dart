import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/pages/admin_courts_page.dart';
import 'package:footrank/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:footrank/admin/presentation/pages/admin_login_page.dart';
import 'package:footrank/admin/presentation/pages/admin_matches_page.dart';
import 'package:footrank/admin/presentation/pages/admin_teams_page.dart';
import 'package:footrank/admin/presentation/pages/admin_users_page.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/services/supabase_service.dart';

/// Public (not file-private) so [AdminDashboardPage]'s shortcut cards can
/// target a section by name without the shell needing to know anything
/// about dashboard internals -- it just receives an [AdminSection] back.
enum AdminSection { dashboard, courts, matches, teams, users }

const _phoneBreakpoint = 700.0;

const _sections = [
  (AdminSection.dashboard, Icons.dashboard_outlined, 'Dashboard'),
  (AdminSection.courts, Icons.place_outlined, 'Courts'),
  (AdminSection.matches, Icons.sports_soccer_outlined, 'Matches'),
  (AdminSection.teams, Icons.shield_outlined, 'Teams'),
  (AdminSection.users, Icons.people_outline, 'Users'),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final _adminRepo = AdminRepository();

  // null = still checking; false = show login; true = show the panel.
  bool? _authorized;
  AdminSection _section = AdminSection.dashboard;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
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
      AdminDashboardPage(onNavigate: (s) => setState(() => _section = s)),
      const AdminCourtsPage(),
      const AdminMatchesPage(),
      const AdminTeamsPage(),
      const AdminUsersPage(),
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
                        style: Theme.of(context).textTheme.titleMedium!.copyWith(
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
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.black.withValues(alpha: 0.28),
          indicatorColor: AppColors.brand(context).withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? AppColors.brand(context)
                  : Theme.of(context).hintColor,
            ),
          ),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: AdminSection.values.indexOf(section),
          onDestinationSelected: (i) => onSelect(AdminSection.values[i]),
          destinations: [
            for (final s in _sections)
              NavigationDestination(
                icon: Icon(s.$2, color: Theme.of(context).hintColor),
                selectedIcon: Icon(s.$2, color: AppColors.brand(context)),
                label: s.$3,
              ),
          ],
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
            for (final s in _sections)
              _NavItem(
                icon: s.$2,
                label: s.$3,
                selected: section == s.$1,
                onTap: () => onSelect(s.$1),
              ),
            const Spacer(),
            _NavItem(
              icon: Icons.logout,
              label: 'Sign out',
              selected: false,
              onTap: onSignOut,
            ),
          ],
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
    final accent = AppColors.brand(context);
    final color = selected ? accent : Theme.of(context).hintColor;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
