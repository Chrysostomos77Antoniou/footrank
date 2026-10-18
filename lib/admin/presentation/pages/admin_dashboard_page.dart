import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/presentation/pages/admin_shell.dart'
    show AdminSection;
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/core/widgets/status_chip.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/team_model.dart';

const _maxContentWidth = 1180.0;

class AdminDashboardPage extends StatefulWidget {
  final ValueChanged<AdminSection> onNavigate;

  /// Injected in widget tests; production uses the real repository.
  final AdminRepository? repo;

  const AdminDashboardPage({super.key, required this.onNavigate, this.repo});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late final AdminRepository _repo = widget.repo ?? AdminRepository();
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // The IndexedStack keeps this page alive between visits, so a manual
  // refresh keeps the numbers honest. FutureBuilder holds the previous data
  // while the new future runs, so refreshing never flashes a skeleton.
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    // Also re-fetch the Players / Teams / Matches / Courts lists.
    triggerAppRefresh();
    final future = _load();
    setState(() {
      _refreshing = true;
      _future = future;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    String message;
    try {
      // Hold the spinner for at least one full turn so a fast reload is
      // still visibly acknowledged.
      await Future.wait<void>([
        future.then((_) {}),
        Future<void>.delayed(const Duration(milliseconds: 700)),
      ]);
      message = 'Everything updated';
    } catch (_) {
      message = 'Could not refresh. Check your connection and try again.';
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<_DashboardData> _load() async {
    final results = await Future.wait<Object>([
      _repo.fetchAllOpenRequests(),
      _repo.fetchAllPendingProposals(),
      _repo.fetchDisputedMatches(),
      _repo.fetchFlaggedUsers(),
      _repo.fetchAllTeams(),
      _repo.fetchAllCourts(),
      _repo.fetchAllMatches(),
      _repo.fetchUserGrowth(),
    ]);
    return _DashboardData(
      openRequests: (results[0] as List).length,
      pendingProposals: (results[1] as List).length,
      disputedMatches: (results[2] as List).length,
      flaggedUsers: (results[3] as List).length,
      teams: results[4] as List<TeamModel>,
      courts: results[5] as List<AdminCourtModel>,
      matches: results[6] as List<MatchModel>,
      users: results[7] as List<({DateTime createdAt, int matchesPlayed})>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // A faint lime wash in the corner -- depth without a heavy gradient.
        Positioned(
          top: -AppSpacing.xl - 160,
          left: -AppSpacing.xl - 120,
          child: IgnorePointer(
            child: Container(
              width: 640,
              height: 520,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.lime.withValues(alpha: 0.055),
                    AppColors.lime.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GreetingHeader(
                        data: data,
                        refreshing: _refreshing,
                        onRefresh: _refresh,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AsyncSwitcher(
                        switcherKey: data == null ? 'loading' : 'content',
                        child: data == null
                            ? const _DashboardSkeleton()
                            : _DashboardContent(
                                data: data,
                                onNavigate: widget.onNavigate,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DashboardData {
  final int openRequests;
  final int pendingProposals;
  final int disputedMatches;
  final int flaggedUsers;
  final List<TeamModel> teams; // already ordered by rating, best first
  final List<AdminCourtModel> courts;
  final List<MatchModel> matches; // newest scheduled first
  final List<({DateTime createdAt, int matchesPlayed})> users;

  const _DashboardData({
    required this.openRequests,
    required this.pendingProposals,
    required this.disputedMatches,
    required this.flaggedUsers,
    required this.teams,
    required this.courts,
    required this.matches,
    required this.users,
  });

  int get attention =>
      openRequests +
      pendingProposals +
      disputedMatches +
      flaggedUsers +
      upcomingCourtsToConfirm +
      upcomingUnpaid;

  // ---- growth ----
  int get totalPlayers => users.length;

  int get activePlayers => users.where((u) => u.matchesPlayed > 0).length;

  int _signupsBetween(Duration from, Duration to) {
    final now = DateTime.now();
    return users
        .where(
          (u) =>
              u.createdAt.isAfter(now.subtract(from)) &&
              !u.createdAt.isAfter(now.subtract(to)),
        )
        .length;
  }

  int get newPlayers7d =>
      _signupsBetween(const Duration(days: 7), Duration.zero);
  int get newPlayersPrev7d =>
      _signupsBetween(const Duration(days: 14), const Duration(days: 7));

  // ---- matches ----
  List<MatchModel> get _live =>
      matches.where((m) => m.status != 'cancelled').toList();

  Iterable<MatchModel> get completed =>
      matches.where((m) => m.status == 'completed');

  int playedWithin(Duration d) {
    final since = DateTime.now().subtract(d);
    return completed.where((m) => m.scheduledAt.isAfter(since)).length;
  }

  /// Matches still to be played, soonest first.
  List<MatchModel> get upcoming {
    final now = DateTime.now();
    final list =
        _live
            .where((m) => m.status != 'completed' && m.scheduledAt.isAfter(now))
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return list;
  }

  List<MatchModel> get upcoming7d {
    final limit = DateTime.now().add(const Duration(days: 7));
    return upcoming.where((m) => m.scheduledAt.isBefore(limit)).toList();
  }

  int get upcomingCourtsToConfirm =>
      upcoming.where((m) => m.courtBookingStatus == 'pending').length;

  int get upcomingUnpaid =>
      upcoming.where((m) => m.paymentStatus == 'unpaid').length;

  /// Share of the last 30 days' played matches whose fee is paid, or null
  /// when nothing was played.
  double? get feeCollection30d {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final played = completed.where((m) => m.scheduledAt.isAfter(since));
    if (played.isEmpty) return null;
    final paid = played.where((m) => m.paymentStatus == 'paid').length;
    return paid / played.length;
  }
}

// ---------------------------------------------------------------- header

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _GreetingHeader extends StatelessWidget {
  final _DashboardData? data;
  final VoidCallback onRefresh;
  final bool refreshing;
  const _GreetingHeader({
    required this.data,
    required this.onRefresh,
    required this.refreshing,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final hint = Theme.of(context).hintColor;
    final phone = isAdminPhone(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}'
              .toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: hint,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        GradientText(
          phone ? '$greeting,\nChrysostomos' : '$greeting, Chrysostomos',
          style: Theme.of(context).textTheme.displayMedium!.copyWith(
            fontSize: phone ? 26 : 28,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Here is how FootRank looks right now.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: hint, fontSize: 13),
        ),
      ],
    );
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (data != null) _StatusPill(attention: data!.attention),
              const Spacer(),
              _RefreshButton(refreshing: refreshing, onRefresh: onRefresh),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}'
                    .toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: hint,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              GradientText(
                '$greeting, Chrysostomos',
                style: Theme.of(context).textTheme.displayMedium!.copyWith(
                  fontSize: 28,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Here is how FootRank looks right now.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: hint, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (data != null) _StatusPill(attention: data!.attention),
        const SizedBox(width: AppSpacing.xs),
        _RefreshButton(refreshing: refreshing, onRefresh: onRefresh),
      ],
    );
  }
}

/// Refresh icon that spins while the dashboard reloads.
class _RefreshButton extends StatefulWidget {
  final bool refreshing;
  final VoidCallback onRefresh;
  const _RefreshButton({required this.refreshing, required this.onRefresh});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(covariant _RefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.refreshing && !old.refreshing) {
      _spin.repeat();
    } else if (!widget.refreshing && old.refreshing) {
      // Finish the current turn instead of snapping back.
      _spin.animateTo(1, curve: Curves.easeOut).whenComplete(_spin.reset);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminPressScale(
      child: IconButton(
        tooltip: widget.refreshing ? 'Refreshing…' : 'Refresh',
        onPressed: widget.refreshing ? null : widget.onRefresh,
        icon: RotationTransition(
          turns: _spin,
          child: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ),
    );
  }
}

/// "All clear" / "3 need attention" -- the one-glance answer to the question
/// this page exists to answer.
class _StatusPill extends StatelessWidget {
  final int attention;
  const _StatusPill({required this.attention});

  @override
  Widget build(BuildContext context) {
    final clear = attention == 0;
    final color = clear ? AppColors.success : AppColors.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSemantic.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          clear
              ? Icon(Icons.check_circle_rounded, size: 15, color: color)
              : PulseDot(color: color, size: 8),
          const SizedBox(width: 8),
          Text(
            clear ? 'All clear' : '$attention need attention',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- content

class _DashboardContent extends StatelessWidget {
  final _DashboardData data;
  final ValueChanged<AdminSection> onNavigate;
  const _DashboardContent({required this.data, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final activeCourts = data.courts.where((c) => c.active).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('NEEDS ATTENTION'),
        const SizedBox(height: AppSpacing.sm),
        _AttentionSection(data: data, onNavigate: onNavigate),
        const SizedBox(height: AppSpacing.xl),
        const _SectionLabel('THE PULSE'),
        const SizedBox(height: AppSpacing.sm),
        AdminGrid(
          minTileWidth: 240,
          count: 4,
          itemBuilder: (i, w) => switch (i) {
            0 => _PulseTile(
              index: 0,
              icon: Icons.person_add_rounded,
              color: AppColors.brand(context),
              value: '${data.newPlayers7d}',
              intValue: data.newPlayers7d,
              label: 'New players · 7 days',
              trend: _Trend.vs(data.newPlayers7d, data.newPlayersPrev7d),
              foot: '${data.totalPlayers} players in total',
              onTap: () => onNavigate(AdminSection.users),
            ),
            1 => _PulseTile(
              index: 1,
              icon: Icons.sports_soccer_rounded,
              color: AppColors.success,
              value: '${data.playedWithin(const Duration(days: 30))}',
              intValue: data.playedWithin(const Duration(days: 30)),
              label: 'Matches played · 30 days',
              foot:
                  '${data.playedWithin(const Duration(days: 7))} in the last 7 days',
              onTap: () => onNavigate(AdminSection.matches),
            ),
            2 => _PulseTile(
              index: 2,
              icon: Icons.calendar_month_rounded,
              color: AppColors.gold,
              value: '${data.upcoming7d.length}',
              intValue: data.upcoming7d.length,
              label: 'Coming up · next 7 days',
              foot: data.upcoming.isEmpty
                  ? 'Nothing scheduled yet'
                  : 'Next: ${_shortWhen(data.upcoming.first.scheduledAt)}',
              onTap: () => onNavigate(AdminSection.matches),
            ),
            _ => _PulseTile(
              index: 3,
              icon: Icons.euro_rounded,
              color: AppColors.success,
              value: data.feeCollection30d == null
                  ? '—'
                  : '${(data.feeCollection30d! * 100).round()}%',
              label: 'Fees collected · 30 days',
              foot: data.feeCollection30d == null
                  ? 'No matches played'
                  : 'of matches played',
              onTap: () => onNavigate(AdminSection.matches),
            ),
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionLabel('OVERVIEW'),
        const SizedBox(height: AppSpacing.sm),
        AdminGrid(
          minTileWidth: 240,
          phoneColumns: 1,
          count: 3,
          itemBuilder: (i, w) => switch (i) {
            0 => _OverviewTile(
              index: 4,
              icon: Icons.shield_rounded,
              value: data.teams.length,
              label: 'Active teams',
              onTap: () => onNavigate(AdminSection.teams),
            ),
            1 => _OverviewTile(
              index: 5,
              icon: Icons.place_rounded,
              value: data.courts.length,
              label: 'Courts · $activeCourts active',
              onTap: () => onNavigate(AdminSection.courts),
            ),
            _ => _OverviewTile(
              index: 6,
              icon: Icons.people_alt_rounded,
              value: data.totalPlayers,
              label: 'Players · ${data.activePlayers} have played',
              onTap: () => onNavigate(AdminSection.users),
            ),
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 820;
            final top = _TopTeamsCard(
              teams: data.teams.take(5).toList(),
              onViewAll: () => onNavigate(AdminSection.teams),
            );
            final latest = _LatestMatchesCard(
              matches: data.matches.take(5).toList(),
              onViewAll: () => onNavigate(AdminSection.matches),
            );
            if (!wide) {
              return Column(
                children: [
                  top,
                  const SizedBox(height: AppSpacing.md),
                  latest,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: top),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: latest),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

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

// ----------------------------------------------------------------- tiles

class _IconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconChip({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) =>
      AdminIconChip(icon: icon, color: color, size: 40);
}

String _shortWhen(DateTime d) {
  final l = d.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${_weekdays[l.weekday - 1].substring(0, 3)} ${l.day} '
      '${_months[l.month - 1].substring(0, 3)}, $hh:$mm';
}

/// "▲ 2 vs prior 7 days" -- the direction a number moved, in one glance.
class _Trend {
  final String text;
  final Color? color; // null = neutral
  const _Trend(this.text, this.color);

  factory _Trend.vs(int now, int before) {
    final d = now - before;
    if (d == 0) return const _Trend('Same as the 7 days before', null);
    return d > 0
        ? _Trend('▲ $d vs the 7 days before', AppColors.success)
        : _Trend('▼ ${-d} vs the 7 days before', AppColors.danger);
  }
}

/// What needs a human: a calm all-clear when nothing does, otherwise one
/// tappable tile per queue that has work in it.
class _AttentionSection extends StatelessWidget {
  final _DashboardData data;
  final ValueChanged<AdminSection> onNavigate;
  const _AttentionSection({required this.data, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brand(context);
    final items = <_AttentionTile Function(int index)>[
      if (data.disputedMatches > 0)
        (i) => _AttentionTile(
          index: i,
          icon: Icons.gavel_rounded,
          label: 'Disputed matches',
          count: data.disputedMatches,
          color: AppColors.gold,
          onTap: () => onNavigate(AdminSection.matches),
        ),
      if (data.flaggedUsers > 0)
        (i) => _AttentionTile(
          index: i,
          icon: Icons.flag_rounded,
          label: 'Flagged players',
          count: data.flaggedUsers,
          color: AppColors.danger,
          onTap: () => onNavigate(AdminSection.users),
        ),
      if (data.upcomingCourtsToConfirm > 0)
        (i) => _AttentionTile(
          index: i,
          icon: Icons.event_available_rounded,
          label: 'Upcoming, court to confirm',
          count: data.upcomingCourtsToConfirm,
          color: AppColors.gold,
          onTap: () => onNavigate(AdminSection.matches),
        ),
      if (data.upcomingUnpaid > 0)
        (i) => _AttentionTile(
          index: i,
          icon: Icons.euro_rounded,
          label: 'Upcoming, fee unpaid',
          count: data.upcomingUnpaid,
          color: AppColors.gold,
          onTap: () => onNavigate(AdminSection.matches),
        ),
      if (data.openRequests > 0)
        (i) => _AttentionTile(
          index: i,
          icon: Icons.person_search_rounded,
          label: 'Open match requests',
          count: data.openRequests,
          color: brand,
          onTap: () => onNavigate(AdminSection.matches),
        ),
      if (data.pendingProposals > 0)
        (i) => _AttentionTile(
          index: i,
          icon: Icons.pending_actions_rounded,
          label: 'Pending proposals',
          count: data.pendingProposals,
          color: brand,
          onTap: () => onNavigate(AdminSection.matches),
        ),
    ];

    if (items.isEmpty) {
      return FadeSlideIn(
        animateOnceId: 'admin-all-clear',
        offsetY: 8,
        child: AdminTile(
          accent: AppColors.success,
          lit: true,
          watermark: '✅',
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          builder: (context, _) => Row(
            children: [
              const AdminIconChip(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                size: 40,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nothing needs your review',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No disputes, flagged players, open requests or pending '
                      'proposals right now.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AdminGrid(
      minTileWidth: 240,
      phoneColumns: 1,
      count: items.length,
      itemBuilder: (i, w) => items[i](i),
    );
  }
}

/// A headline number with context: what it is, how it moved, what's next.
class _PulseTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final Color color;
  final String value;

  /// When set the number counts up to this instead of showing [value].
  final int? intValue;
  final String label;
  final _Trend? trend;
  final String foot;
  final VoidCallback onTap;

  const _PulseTile({
    required this.index,
    required this.icon,
    required this.color,
    required this.value,
    this.intValue,
    required this.label,
    this.trend,
    required this.foot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final numStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: isAdminPhone(context) ? 30 : 36,
      height: 1,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return FadeSlideIn(
      delay: AppMotion.staggerFor(index),
      animateOnceId: 'admin-pulse-$label',
      offsetY: 8,
      child: AdminTile(
        accent: color,
        onTap: onTap,
        watermark: adminEmojiFor(icon),
        padding: const EdgeInsets.all(AppSpacing.md),
        builder: (context, hovered) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminIconChip(icon: icon, color: color, size: 40),
            const SizedBox(height: AppSpacing.md),
            intValue != null
                ? AnimatedCount(
                    intValue!,
                    duration: AppMotion.count,
                    style: numStyle,
                  )
                : Text(value, style: numStyle),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (trend != null)
              Text(
                trend!.text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: trend!.color ?? hint,
                ),
              ),
            Text(foot, style: TextStyle(fontSize: 12, color: hint)),
          ],
        ),
      ),
    );
  }
}

/// A count that needs a decision. Lights up in its colour when there is work
/// to do; settles into a quiet "All clear" when there isn't.
class _AttentionTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _AttentionTile({
    required this.index,
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final hint = Theme.of(context).hintColor;
    final reduce = reduceMotion(context);

    return FadeSlideIn(
      delay: AppMotion.staggerFor(index),
      animateOnceId: 'admin-attn-$label',
      offsetY: 8,
      child: AdminTile(
        accent: active ? color : AppColors.brand(context),
        watermark: adminEmojiFor(icon),
        lit: active,
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        builder: (context, hovered) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconChip(icon: icon, color: active ? color : hint),
                const Spacer(),
                if (active) PulseDot(color: color, size: 8),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AnimatedCount(
              count,
              duration: AppMotion.count,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 36,
                height: 1,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  active ? 'Review' : 'All clear',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? color : hint,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedSlide(
                  offset: Offset(hovered && active && !reduce ? 0.3 : 0, 0),
                  duration: const Duration(milliseconds: 180),
                  curve: kAdminEaseOut,
                  child: Icon(
                    active ? Icons.arrow_forward_rounded : Icons.check_rounded,
                    size: 14,
                    color: active ? color : hint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact total with its own jump-to link.
class _OverviewTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final int value;
  final String label;
  final VoidCallback onTap;

  const _OverviewTile({
    required this.index,
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brand(context);
    final reduce = reduceMotion(context);
    return FadeSlideIn(
      delay: AppMotion.staggerFor(index),
      animateOnceId: 'admin-overview-$label',
      offsetY: 8,
      child: AdminTile(
        onTap: onTap,
        watermark: adminEmojiFor(icon),
        builder: (context, hovered) => Row(
          children: [
            _IconChip(icon: icon, color: brand),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedCount(
                    value,
                    duration: AppMotion.count,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSlide(
              offset: Offset(hovered && !reduce ? 0.3 : 0, 0),
              duration: const Duration(milliseconds: 180),
              curve: kAdminEaseOut,
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: hovered ? brand : Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- cards

class _PanelCard extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  const _PanelCard({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brand(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xxs,
              AppSpacing.xxs,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AdminPressScale(
                  child: TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      foregroundColor: brand,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text('$actionLabel →'),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _TopTeamsCard extends StatelessWidget {
  final List<TeamModel> teams;
  final VoidCallback onViewAll;
  const _TopTeamsCard({required this.teams, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Top teams',
      actionLabel: 'All teams',
      onAction: onViewAll,
      child: teams.isEmpty
          ? const AdminEmptyState(
              icon: Icons.shield_outlined,
              message: 'No teams yet.',
            )
          : Column(
              children: [
                for (var i = 0; i < teams.length; i++)
                  AdminRowTile(
                    onTap: onViewAll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        RankBadge(rank: i + 1, size: 28),
                        const SizedBox(width: AppSpacing.sm),
                        GradientAvatar(
                          name: teams[i].name,
                          imageUrl: teams[i].logoUrl,
                          radius: 15,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                teams[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                [
                                  if (teams[i].city != null) teams[i].city!,
                                  teams[i].record,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        LevelBadge(value: teams[i].rating, size: 26),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _LatestMatchesCard extends StatelessWidget {
  final List<MatchModel> matches;
  final VoidCallback onViewAll;
  const _LatestMatchesCard({required this.matches, required this.onViewAll});

  static String _when(DateTime d) {
    final l = d.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day} ${_shortMonths[l.month - 1]} · $hh:$mm';
  }

  /// Score + status. On a phone they stack (status over score) so the team
  /// names keep their width instead of colliding with the score.
  static Widget _trailing(BuildContext context, MatchModel m) {
    final hasScore = m.homeScore != null && m.awayScore != null;
    final score = Text(
      '${m.homeScore}–${m.awayScore}',
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    final chip = m.status == 'cancelled'
        ? const _CancelledChip()
        : StatusChip.fromString(m.status, disputed: m.scoreDisputed);
    if (isAdminPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          if (hasScore) ...[const SizedBox(height: 4), score],
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasScore) ...[score, const SizedBox(width: AppSpacing.sm)],
        chip,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Latest matches',
      actionLabel: 'All matches',
      onAction: onViewAll,
      child: matches.isEmpty
          ? const AdminEmptyState(
              icon: Icons.sports_soccer_outlined,
              message: 'No matches yet.',
            )
          : Column(
              children: [
                for (final m in matches)
                  AdminRowTile(
                    onTap: onViewAll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.homeTeamName ?? '?'} vs ${m.awayTeamName ?? '?'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${m.city} · ${_when(m.scheduledAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _trailing(context, m),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CancelledChip extends StatelessWidget {
  const _CancelledChip();

  @override
  Widget build(BuildContext context) {
    final color = AppColors.muted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSemantic.statusPillRadius),
      ),
      child: Text(
        'Cancelled',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- skeleton

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('NEEDS ATTENTION'),
        const SizedBox(height: AppSpacing.sm),
        const ShimmerBox(width: double.infinity, height: 70, radius: 20),
        const SizedBox(height: AppSpacing.xl),
        const _SectionLabel('THE PULSE'),
        const SizedBox(height: AppSpacing.sm),
        AdminGrid(
          minTileWidth: 240,
          count: 4,
          itemBuilder: (i, w) => ShimmerBox(width: w, height: 160, radius: 20),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionLabel('OVERVIEW'),
        const SizedBox(height: AppSpacing.sm),
        AdminGrid(
          minTileWidth: 240,
          count: 3,
          itemBuilder: (i, w) => ShimmerBox(width: w, height: 76, radius: 20),
        ),
      ],
    );
  }
}
