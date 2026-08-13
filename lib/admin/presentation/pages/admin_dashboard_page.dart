import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/pages/admin_shell.dart'
    show AdminSection;
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';

class AdminDashboardPage extends StatefulWidget {
  final ValueChanged<AdminSection> onNavigate;
  const AdminDashboardPage({super.key, required this.onNavigate});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _repo = AdminRepository();
  late Future<_DashboardCounts> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardCounts> _load() async {
    final results = await Future.wait([
      _repo.fetchAllOpenRequests(),
      _repo.fetchAllPendingProposals(),
      _repo.fetchDisputedMatches(),
      _repo.fetchFlaggedUsers(),
      _repo.fetchAllTeams(),
      _repo.fetchAllCourts(),
    ]);
    return _DashboardCounts(
      openRequests: results[0].length,
      pendingProposals: results[1].length,
      disputedMatches: results[2].length,
      flaggedUsers: results[3].length,
      teams: results[4].length,
      courts: results[5].length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: FadeSlideIn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminHeader(
              title: 'Dashboard',
              subtitle: 'What needs your attention right now.',
            ),
            const SizedBox(height: AppSpacing.xl),
            FutureBuilder<_DashboardCounts>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final c = snapshot.data!;
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    SizedBox(
                      width: 260,
                      child: AdminStatCard(
                        icon: Icons.flag,
                        value: '${c.flaggedUsers}',
                        label: 'Flagged users',
                        accent: AppColors.danger,
                        onTap: () => widget.onNavigate(AdminSection.users),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: AdminStatCard(
                        icon: Icons.gavel,
                        value: '${c.disputedMatches}',
                        label: 'Disputed matches',
                        accent: AppColors.gold,
                        onTap: () => widget.onNavigate(AdminSection.matches),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: AdminStatCard(
                        icon: Icons.person_search_outlined,
                        value: '${c.openRequests}',
                        label: 'Open requests',
                        onTap: () => widget.onNavigate(AdminSection.matches),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: AdminStatCard(
                        icon: Icons.pending_actions_outlined,
                        value: '${c.pendingProposals}',
                        label: 'Pending proposals',
                        onTap: () => widget.onNavigate(AdminSection.matches),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: AdminStatCard(
                        icon: Icons.groups_outlined,
                        value: '${c.teams}',
                        label: 'Active teams',
                        onTap: () => widget.onNavigate(AdminSection.teams),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: AdminStatCard(
                        icon: Icons.place_outlined,
                        value: '${c.courts}',
                        label: 'Courts on file',
                        onTap: () => widget.onNavigate(AdminSection.courts),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _DashboardSectionLabel('SHORTCUTS'),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                // 4-across on desktop, 2-across once the sidebar squeezes
                // things down (matches the mobile app's own MANAGE grid
                // breakpoint logic -- roomy tiles over a cramped row).
                final columns = constraints.maxWidth >= 640 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.35,
                  children: [
                    _ShortcutCard(
                      icon: Icons.place_outlined,
                      title: 'Courts',
                      subtitle: 'Add, edit, activate',
                      onTap: () => widget.onNavigate(AdminSection.courts),
                    ),
                    _ShortcutCard(
                      icon: Icons.sports_soccer_outlined,
                      title: 'Matches',
                      subtitle: 'Disputes, requests, cancellations',
                      onTap: () => widget.onNavigate(AdminSection.matches),
                    ),
                    _ShortcutCard(
                      icon: Icons.shield_outlined,
                      title: 'Teams',
                      subtitle: 'Rosters & ratings',
                      onTap: () => widget.onNavigate(AdminSection.teams),
                    ),
                    _ShortcutCard(
                      icon: Icons.people_outline,
                      title: 'Users',
                      subtitle: 'Search & moderate',
                      onTap: () => widget.onNavigate(AdminSection.users),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Small uppercase eyebrow label -- same treatment as the mobile app's
/// "MANAGE" section on Home, so this reads as the equivalent shortcuts area.
class _DashboardSectionLabel extends StatelessWidget {
  final String text;
  const _DashboardSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}

/// A tappable tile linking straight into a section -- the admin-panel
/// equivalent of the mobile app's Home "MANAGE" grid cards.
class _ShortcutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brand(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md - 2),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accent, size: 20),
          ),
          const Spacer(),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

class _DashboardCounts {
  final int openRequests;
  final int pendingProposals;
  final int disputedMatches;
  final int flaggedUsers;
  final int teams;
  final int courts;

  const _DashboardCounts({
    required this.openRequests,
    required this.pendingProposals,
    required this.disputedMatches,
    required this.flaggedUsers,
    required this.teams,
    required this.courts,
  });
}
