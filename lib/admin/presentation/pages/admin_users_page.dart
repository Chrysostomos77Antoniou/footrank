import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/widgets/admin_detail_parts.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/core/widgets/feedback.dart';

class AdminUsersPage extends StatefulWidget {
  /// Injected in widget tests; production uses the real repository.
  final AdminRepository? repo;

  const AdminUsersPage({super.key, this.repo});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

enum _FilterMode { all, flagged }

enum _UserSort {
  name('Name A–Z'),
  newest('Newest first'),
  oldest('Oldest first'),
  power('Highest power'),
  reliability('Lowest reliability');

  final String label;
  const _UserSort(this.label);

  int compare(UserModel a, UserModel b) => switch (this) {
    name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    newest => b.createdAt.compareTo(a.createdAt),
    oldest => a.createdAt.compareTo(b.createdAt),
    power => b.elo.compareTo(a.elo),
    reliability => a.reliability.compareTo(b.reliability),
  };
}

const _kMonths = [
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

String _joined(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_kMonths[l.month - 1]} ${l.year}';
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  late final AdminRepository _repo = widget.repo ?? AdminRepository();
  final _searchCtrl = TextEditingController();
  late Future<List<UserModel>> _future;
  bool _searching = false;
  _FilterMode _filter = _FilterMode.all;
  _UserSort _sort = _UserSort.name;
  String? _city;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAllUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<UserModel>> _fetchForFilter() => _filter == _FilterMode.all
      ? _repo.fetchAllUsers()
      : _repo.fetchFlaggedUsers();

  void _search(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searching = false;
        _future = _fetchForFilter();
      });
      return;
    }
    setState(() {
      _searching = true;
      _future = _repo.searchUsers(query);
    });
  }

  void _setFilter(_FilterMode mode) {
    setState(() {
      _filter = mode;
      _future = _fetchForFilter();
    });
  }

  Future<void> _openUser(UserModel user) async {
    final changed = await showAdminDialog<bool>(
      context: context,
      builder: (_) => _UserDetailDialog(user: user, repo: _repo),
    );
    if (changed == true) {
      setState(() {
        _future = _searching
            ? _repo.searchUsers(_searchCtrl.text)
            : _fetchForFilter();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = isAdminPhone(context);
    // On a phone these join the city/sort chips in one scrolling row.
    final modeChips = <Widget>[
      AdminFilterChip(
        label: phone ? 'All' : 'All players',
        selected: _filter == _FilterMode.all,
        onTap: () => _setFilter(_FilterMode.all),
      ),
      AdminFilterChip(
        label: phone ? 'Flagged' : 'Flagged only',
        icon: Icons.flag_outlined,
        selected: _filter == _FilterMode.flagged,
        onTap: () => _setFilter(_FilterMode.flagged),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeader(
          title: 'Users',
          subtitle: 'Search any player, or review flagged accounts.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AdminSearchField(
          controller: _searchCtrl,
          onChanged: _search,
          hint: 'Search by name or username…',
        ),
        const SizedBox(height: AppSpacing.md),
        if (_searching)
          Text(
            'Search results',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          )
        else if (!phone)
          AdminFilterBar(children: modeChips),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: AdminAsyncBody<List<UserModel>>(
            future: _future,
            builder: (context, data) {
              if (data.isEmpty) {
                final flaggedView =
                    !_searching && _filter == _FilterMode.flagged;
                final empty = AdminEmptyState(
                  icon: _searching
                      ? Icons.search_off
                      : (flaggedView
                            ? Icons.verified_user_outlined
                            : Icons.people_outline),
                  message: _searching
                      ? 'No matching users.'
                      : (flaggedView
                            ? 'No flagged accounts.'
                            : 'No users yet.'),
                );
                if (!phone || _searching) return empty;
                // Keep the toggle reachable so "Flagged only" can be undone.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminFilterBar(children: modeChips),
                    Expanded(child: empty),
                  ],
                );
              }
              // City list comes from whoever is in the current result, so
              // it always matches what you could actually pick.
              final cityCounts = <String, int>{};
              for (final u in data) {
                final c = (u.city ?? '').trim();
                if (c.isNotEmpty) cityCounts[c] = (cityCounts[c] ?? 0) + 1;
              }
              final cities = cityCounts.keys.toList()..sort();
              final city = cityCounts.containsKey(_city) ? _city : null;
              final users =
                  (city == null
                        ? List<UserModel>.of(data)
                        : data
                              .where((u) => (u.city ?? '').trim() == city)
                              .toList())
                    ..sort(_sort.compare);

              final controls = Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AdminFilterBar(
                  children: [
                    if (phone && !_searching) ...modeChips,
                    AdminPopover(
                      triggerBuilder: (context, toggle, open) =>
                          AdminFilterChip(
                            icon: Icons.location_city_outlined,
                            label: city ?? 'All cities',
                            selected: city != null,
                            caret: true,
                            open: open,
                            onTap: toggle,
                          ),
                      menuBuilder: (context, close) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdminMenuItem(
                            label: 'All cities',
                            hint: '${data.length}',
                            checked: city == null,
                            onTap: () {
                              setState(() => _city = null);
                              close();
                            },
                          ),
                          for (final name in cities)
                            AdminMenuItem(
                              label: name,
                              hint: '${cityCounts[name]}',
                              checked: city == name,
                              onTap: () {
                                setState(() => _city = name);
                                close();
                              },
                            ),
                        ],
                      ),
                    ),
                    AdminPopover(
                      width: 210,
                      triggerBuilder: (context, toggle, open) =>
                          AdminFilterChip(
                            icon: Icons.swap_vert_rounded,
                            label: _sort.label,
                            selected: _sort != _UserSort.name,
                            caret: true,
                            open: open,
                            onTap: toggle,
                          ),
                      menuBuilder: (context, close) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final o in _UserSort.values)
                            AdminMenuItem(
                              label: o.label,
                              checked: _sort == o,
                              onTap: () {
                                setState(() => _sort = o);
                                close();
                              },
                            ),
                        ],
                      ),
                    ),
                    if (city != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Showing ${users.length} of ${data.length}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Theme.of(context).hintColor),
                        ),
                      ),
                  ],
                ),
              );
              if (users.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    controls,
                    const Expanded(
                      child: AdminEmptyState(
                        icon: Icons.people_outline,
                        message: 'No players in this city.',
                      ),
                    ),
                  ],
                );
              }
              final avgRel = users.isEmpty
                  ? 0
                  : (users.fold<int>(0, (a, u) => a + u.reliability) /
                            users.length)
                        .round();
              final flaggedCount = users.where((u) => u.flagged).length;
              final disputes = users.fold<int>(0, (a, u) => a + u.disputeCount);
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    controls,
                    AdminGrid(
                      phoneScroll: true,
                      minTileWidth: 200,
                      count: 4,
                      itemBuilder: (i, w) => switch (i) {
                        0 => AdminMiniStat(
                          index: 0,
                          icon: Icons.people_alt_rounded,
                          value: '${users.length}',
                          label: _searching ? 'Matching players' : 'Players',
                          color: AppColors.brand(context),
                        ),
                        1 => AdminMiniStat(
                          index: 1,
                          icon: Icons.verified_rounded,
                          value: '$avgRel%',
                          label: 'Average reliability',
                          color: avgRel >= 80
                              ? AppColors.success
                              : (avgRel >= 60
                                    ? AppColors.gold
                                    : AppColors.danger),
                          progress: avgRel / 100,
                        ),
                        2 => AdminMiniStat(
                          index: 2,
                          icon: Icons.flag_rounded,
                          value: '$flaggedCount',
                          label: 'Flagged accounts',
                          color: AppColors.danger,
                          lit: flaggedCount > 0,
                        ),
                        _ => AdminMiniStat(
                          index: 3,
                          icon: Icons.gavel_rounded,
                          value: '$disputes',
                          label: 'Disputes raised',
                          color: AppColors.gold,
                        ),
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: GlassCard(
                        padding: EdgeInsets.all(
                          isAdminPhone(context)
                              ? AppSpacing.xxs
                              : AppSpacing.sm,
                        ),
                        child: AdminScrollableTable(
                          child: Column(
                            children: [
                              if (!isAdminPhone(context))
                                const AdminTableHeader(
                                  columns: [
                                    'Player',
                                    'City',
                                    'Joined',
                                    'Power',
                                    'Reliability',
                                    'Disputes',
                                    '',
                                  ],
                                  flex: [3, 2, 2, 1, 2, 1, 0],
                                  fixedWidths: [
                                    null,
                                    null,
                                    null,
                                    null,
                                    null,
                                    null,
                                    44,
                                  ],
                                ),
                              for (final u in users)
                                _UserRow(
                                  user: u,
                                  compact: isAdminPhone(context),
                                  onTap: () => _openUser(u),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final bool compact;
  const _UserRow({
    required this.user,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return _compact(context);
    return AdminRowTile(
      onTap: onTap,
      padding: EdgeInsets.zero,
      tint: user.flagged ? AppColors.danger.withValues(alpha: 0.06) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  GradientAvatar(
                    name: user.name,
                    imageUrl: user.avatarUrl,
                    radius: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '@${user.username}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  if (user.flagged)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.flag,
                        size: 15,
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (user.city ?? '').trim().isEmpty ? '—' : user.city!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _joined(user.createdAt),
                maxLines: 1,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [LevelBadge(value: user.elo, size: 26)],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: _ReliabilityBar(value: user.reliability),
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _DisputePill(count: user.disputeCount),
              ),
            ),
            // Fixed-width trailing column so the chevron sits in the same
            // pixel position on every row.
            const SizedBox(
              width: 44,
              child: Icon(Icons.chevron_right, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

extension on _UserRow {
  /// Phone layout: identity on the left, power and reliability stacked on
  /// the right -- everything the table showed, in two lines.
  Widget _compact(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final relColor = user.reliability >= 80
        ? AppColors.success
        : (user.reliability >= 60 ? AppColors.gold : AppColors.danger);
    final detail = [
      if ((user.city ?? '').trim().isNotEmpty) user.city!.trim(),
      'Joined ${_joined(user.createdAt)}',
    ].join(' · ');
    return AdminRowTile(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tint: user.flagged ? AppColors.danger.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          GradientAvatar(name: user.name, imageUrl: user.avatarUrl, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (user.flagged)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.flag,
                          size: 14,
                          color: AppColors.danger,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: hint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LevelBadge(value: user.elo, size: 24),
              const SizedBox(height: 4),
              Text(
                '${user.reliability}%'
                '${user.disputeCount > 0 ? ' · ${user.disputeCount} disp.' : ''}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: user.disputeCount > 0 ? AppColors.gold : relColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReliabilityBar extends StatelessWidget {
  final int value;
  const _ReliabilityBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 80
        ? AppColors.success
        : (value >= 60 ? AppColors.gold : AppColors.danger);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '$value%',
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value.clamp(0, 100)) / 100),
              duration: const Duration(milliseconds: 300),
              curve: kAdminEaseOut,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DisputePill extends StatelessWidget {
  final int count;
  const _DisputePill({required this.count});

  @override
  Widget build(BuildContext context) {
    final hot = count > 0;
    final color = hot ? AppColors.gold : Theme.of(context).hintColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: hot ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _UserDetailDialog extends StatefulWidget {
  final UserModel user;
  final AdminRepository repo;
  const _UserDetailDialog({required this.user, required this.repo});

  @override
  State<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<_UserDetailDialog> {
  late bool _flagged = widget.user.flagged;
  late double _reliability = widget.user.reliability.toDouble();
  bool _saving = false;
  late final Future<({List<AdminUserTeam> teams, List<MatchModel> matches})>
  _extra = _loadExtra();

  Future<({List<AdminUserTeam> teams, List<MatchModel> matches})>
  _loadExtra() async {
    final teams = await widget.repo.fetchUserTeams(widget.user.id);
    final matches = await widget.repo.fetchMatchesForTeams([
      for (final t in teams) t.team.id,
    ]);
    return (teams: teams, matches: matches);
  }

  late final Future<String?> _email =
      widget.repo.fetchUserEmail(widget.user.id);

  late final Future<({String? phone, DateTime? dateOfBirth})> _private =
      widget.repo.fetchUserPrivate(widget.user.id);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repo.setUserModeration(
        userId: widget.user.id,
        flagged: _flagged,
        reliability: _reliability.round(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  GradientAvatar(
                    name: user.name,
                    imageUrl: user.avatarUrl,
                    radius: 26,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '@${user.username}',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  LevelBadge(value: user.elo, size: 40, showLabel: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  _MiniStat(label: 'Matches', value: '${user.matchesPlayed}'),
                  _MiniStat(label: 'Disputes', value: '${user.disputeCount}'),
                  _MiniStat(
                    label: 'Behavior +',
                    value: '${user.behaviorPositive}',
                  ),
                  _MiniStat(
                    label: 'Behavior -',
                    value: '${user.behaviorNegative}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AdminDetailSection('Profile'),
                      AdminInfoRow('Username', '@${user.username}'),
                      FutureBuilder<String?>(
                        future: _email,
                        builder: (context, snap) => AdminInfoRow(
                          'Email',
                          snap.hasError
                              ? 'Could not load'
                              : !snap.hasData && snap.connectionState !=
                                      ConnectionState.done
                                  ? 'Loading…'
                                  : (snap.data ?? 'Not provided'),
                        ),
                      ),
                      FutureBuilder<({String? phone, DateTime? dateOfBirth})>(
                        future: _private,
                        builder: (context, snap) {
                          final String phone;
                          final String dob;
                          if (snap.hasError) {
                            phone = dob = 'Could not load';
                          } else if (!snap.hasData) {
                            phone = dob = 'Loading…';
                          } else {
                            final d = snap.data!;
                            phone = d.phone ?? 'Not provided';
                            dob = d.dateOfBirth == null
                                ? 'Not provided'
                                : adminDate(d.dateOfBirth!);
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AdminInfoRow('Phone', phone),
                              AdminInfoRow('Date of birth', dob),
                            ],
                          );
                        },
                      ),
                      AdminInfoRow('City', user.city ?? 'Not set'),
                      AdminInfoRow('Position', user.position ?? 'Not set'),
                      AdminInfoRow('Joined', adminDate(user.createdAt)),
                      AdminInfoRow(
                        'Rating quiz',
                        user.pwrAssessmentCompletedAt == null
                            ? 'Not completed'
                            : 'Completed ${adminDate(user.pwrAssessmentCompletedAt!)}',
                      ),
                      AdminInfoRow('Power (PWR)', '${user.elo}'),
                      AdminInfoRow('Reliability', '${user.reliability}%'),
                      AdminInfoRow(
                        'Behaviour',
                        '${user.behaviorLabel}  (+${user.behaviorPositive} / -${user.behaviorNegative})',
                      ),
                      AdminInfoRow('Flagged', user.flagged ? 'Yes' : 'No'),
                      AdminInfoRow('Player ID', user.id),
                      FutureBuilder<
                        ({List<AdminUserTeam> teams, List<MatchModel> matches})
                      >(
                        future: _extra,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text(
                              'Could not load teams and matches.',
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                              ),
                            );
                          }
                          final data = snapshot.data;
                          if (data == null) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            );
                          }
                          final myTeams = {for (final t in data.teams) t.team.id};
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AdminDetailSection('Teams'),
                              if (data.teams.isEmpty)
                                Text(
                                  'Not in a team.',
                                  style: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                              for (final t in data.teams)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${t.team.name}'
                                          '${t.team.isDisbanded ? ' (disbanded)' : ''}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${t.role.replaceAll('_', ' ')} · '
                                        '${t.team.record} · since ${adminDate(t.joinedAt)}',
                                        style: TextStyle(
                                          color: Theme.of(context).hintColor,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const AdminDetailSection(
                                "Recent matches of their teams",
                              ),
                              if (data.matches.isEmpty)
                                Text(
                                  'No matches yet.',
                                  style: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                              for (final m in data.matches)
                                AdminMatchTile(match: m, myTeamIds: myTeams),
                            ],
                          );
                        },
                      ),
                      const AdminDetailSection('Disputes and moderation'),
                      Text(
                        'Dispute history',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).hintColor,
                              letterSpacing: 0.6,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      FutureBuilder(
                        future: widget.repo.fetchDisputeHistory(user.id),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            );
                          }
                          final matches = snapshot.data!;
                          if (matches.isEmpty) {
                            return Text(
                              'No disputes on record.',
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (final m in matches)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${m.homeTeamName ?? '?'} vs ${m.awayTeamName ?? '?'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(fontSize: 13),
                                        ),
                                      ),
                                      Text(
                                        m.hasScore
                                            ? '${m.homeScore}-${m.awayScore}'
                                            : 'unresolved',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).hintColor,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Flagged'),
                        subtitle: const Text('Marks the account for review'),
                        value: _flagged,
                        onChanged: (v) => setState(() => _flagged = v),
                      ),
                      Text('Reliability: ${_reliability.round()}%'),
                      Slider(
                        value: _reliability,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${_reliability.round()}%',
                        onChanged: (v) => setState(() => _reliability = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AdminPressScale(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AdminPressScale(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }
}
