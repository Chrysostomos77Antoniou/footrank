import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/widgets/admin_detail_parts.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/team/data/team_repository.dart';

enum _TeamSort {
  power('Highest power'),
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name A–Z'),
  mostMatches('Most matches');

  final String label;
  const _TeamSort(this.label);

  int compare(TeamModel a, TeamModel b) => switch (this) {
    power => b.rating.compareTo(a.rating),
    newest => b.createdAt.compareTo(a.createdAt),
    oldest => a.createdAt.compareTo(b.createdAt),
    name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    mostMatches => (b.wins + b.losses + b.draws).compareTo(
      a.wins + a.losses + a.draws,
    ),
  };
}

class AdminTeamsPage extends StatefulWidget {
  /// Injected in widget tests; production uses the real repository.
  final AdminRepository? repo;

  const AdminTeamsPage({super.key, this.repo});

  @override
  State<AdminTeamsPage> createState() => _AdminTeamsPageState();
}

class _AdminTeamsPageState extends State<AdminTeamsPage> {
  late final AdminRepository _repo = widget.repo ?? AdminRepository();
  List<TeamModel>? _teams;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final teams = await _repo.fetchAllTeams();
      if (!mounted) return;
      setState(() {
        _teams = teams;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _open(TeamModel team) => showAdminDialog<void>(
    context: context,
    builder: (_) => _TeamDetailDialog(team: team, repo: _repo),
  );

  @override
  Widget build(BuildContext context) {
    final teams = _teams;
    final Widget body;
    final String bodyKey;
    if (teams != null) {
      bodyKey = 'content';
      body = AdminTeamsView(teams: teams, onOpen: _open);
    } else if (_error != null) {
      bodyKey = 'error';
      body = Align(
        alignment: Alignment.topCenter,
        child: AdminEmptyState(
          icon: Icons.error_outline,
          message: friendlyError(_error!),
          actionLabel: 'Try again',
          onAction: () {
            setState(() => _error = null);
            _load();
          },
        ),
      );
    } else {
      bodyKey = 'loading';
      body = const AdminTableSkeleton();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeader(
          title: 'Teams',
          subtitle: 'Every active team, ranked by Pitch Power.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AsyncSwitcher(switcherKey: bodyKey, child: body),
        ),
      ],
    );
  }
}

/// Summary strip, search, city filter and the ranked table. Public and free
/// of network code so it can be tested with fake data.
class AdminTeamsView extends StatefulWidget {
  final List<TeamModel> teams;
  final ValueChanged<TeamModel> onOpen;
  const AdminTeamsView({super.key, required this.teams, required this.onOpen});

  @override
  State<AdminTeamsView> createState() => _AdminTeamsViewState();
}

class _AdminTeamsViewState extends State<AdminTeamsView> {
  final _search = TextEditingController();
  String _query = '';
  String? _city;
  _TeamSort _sort = _TeamSort.power;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    setState(() {
      _query = '';
      _city = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rank is global (by Pitch Power), so filtering never renumbers a team.
    final ranked = [...widget.teams]
      ..sort((a, b) => b.rating.compareTo(a.rating));
    final rank = {for (var i = 0; i < ranked.length; i++) ranked[i].id: i + 1};

    final cityCounts = <String, int>{};
    for (final t in ranked) {
      final c = t.city;
      if (c != null && c.isNotEmpty) cityCounts[c] = (cityCounts[c] ?? 0) + 1;
    }
    final cities = cityCounts.keys.toList()..sort();
    final city = cityCounts.containsKey(_city) ? _city : null;

    final q = _query.trim().toLowerCase();
    final shown = ranked.where((t) {
      if (city != null && t.city != city) return false;
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          (t.city?.toLowerCase().contains(q) ?? false);
    }).toList()..sort(_sort.compare);
    final isFiltered = city != null || q.isNotEmpty;

    final avg = ranked.isEmpty
        ? 0
        : (ranked.fold<int>(0, (sum, t) => sum + t.rating) / ranked.length)
              .round();
    final brand = AppColors.brand(context);
    final phone = isAdminPhone(context);
    final searchField = AdminSearchField(
      controller: _search,
      hint: 'Search teams…',
      onChanged: (v) => setState(() => _query = v),
    );
    final cityPopover = AdminPopover(
      triggerBuilder: (context, toggle, open) => AdminFilterChip(
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
            hint: '${ranked.length}',
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
    );
    final sortPopover = AdminPopover(
      width: 210,
      triggerBuilder: (context, toggle, open) => AdminFilterChip(
        icon: Icons.swap_vert_rounded,
        label: _sort.label,
        selected: _sort != _TeamSort.power,
        caret: true,
        open: open,
        onTap: toggle,
      ),
      menuBuilder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in _TeamSort.values)
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
    );
    final Widget? clearButton = isFiltered
        ? AdminPressScale(
            child: TextButton(
              onPressed: _clear,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                foregroundColor: brand,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(
                'Clear · showing ${shown.length} of ${ranked.length}',
              ),
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminGrid(
          phoneScroll: true,
          minTileWidth: 210,
          count: 4,
          itemBuilder: (i, w) => switch (i) {
            0 => AdminMiniStat(
              index: 0,
              icon: Icons.shield_rounded,
              value: '${ranked.length}',
              label: 'Active teams',
              color: brand,
            ),
            1 => AdminMiniStat(
              index: 1,
              icon: Icons.bolt_rounded,
              value: '$avg',
              label: 'Average Pitch Power',
              color: AppColors.gold,
            ),
            2 => AdminMiniStat(
              index: 2,
              icon: Icons.emoji_events_rounded,
              value: ranked.isEmpty ? '—' : ranked.first.name,
              label: 'Top of the table',
              color: AppColors.gold,
            ),
            _ => AdminMiniStat(
              index: 3,
              icon: Icons.location_city_rounded,
              value: '${cityCounts.length}',
              label: cityCounts.length == 1 ? 'City' : 'Cities',
              color: brand,
            ),
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (phone)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: AppSpacing.xs),
              AdminFilterBar(children: [cityPopover, sortPopover, ?clearButton]),
            ],
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: 260, child: searchField),
              cityPopover,
              sortPopover,
              ?clearButton,
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: shown.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: AdminEmptyState(
                    icon: Icons.shield_outlined,
                    message: ranked.isEmpty
                        ? 'No teams yet.'
                        : 'No teams match these filters.',
                    actionLabel: ranked.isEmpty ? null : 'Clear filters',
                    onAction: ranked.isEmpty ? null : _clear,
                  ),
                )
              : FadeSlideIn(
                  child: SizedBox(
                    width: double.infinity,
                    child: GlassCard(
                      padding: EdgeInsets.all(
                        phone ? AppSpacing.xxs : AppSpacing.sm,
                      ),
                      child: AdminScrollableTable(
                        child: Column(
                          children: [
                            if (!phone)
                              const AdminTableHeader(
                                columns: [
                                  '#',
                                  'Team',
                                  'City',
                                  'Power',
                                  'Record',
                                  '',
                                ],
                                flex: [0, 3, 2, 1, 2, 0],
                                fixedWidths: [40, null, null, null, null, 44],
                              ),
                            for (var i = 0; i < shown.length; i++)
                              FadeSlideIn(
                                key: ValueKey(shown[i].id),
                                delay: AppMotion.staggerFor(i),
                                animateOnceId: 'admin-team-${shown[i].id}',
                                offsetY: 6,
                                child: _TeamRow(
                                  team: shown[i],
                                  rank: rank[shown[i].id]!,
                                  compact: phone,
                                  onTap: () => widget.onOpen(shown[i]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  final TeamModel team;
  final int rank;
  final VoidCallback onTap;
  final bool compact;
  const _TeamRow({
    required this.team,
    required this.rank,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final hint = Theme.of(context).hintColor;
      final detail = [
        if (team.city?.trim().isNotEmpty ?? false) team.city!.trim(),
        team.record,
      ].join(' · ');
      return AdminRowTile(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 30, child: RankBadge(rank: rank, size: 24)),
            const SizedBox(width: 6),
            GradientAvatar(name: team.name, imageUrl: team.logoUrl, radius: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
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
            LevelBadge(value: team.rating, size: 26),
          ],
        ),
      );
    }
    return AdminRowTile(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(width: 40, child: RankBadge(rank: rank, size: 26)),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                GradientAvatar(
                  name: team.name,
                  imageUrl: team.logoUrl,
                  radius: 16,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(team.city ?? '—'),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [LevelBadge(value: team.rating, size: 26)],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(team.record),
            ),
          ),
          // Fixed-width trailing column so the chevron sits in the same
          // pixel position on every row.
          const SizedBox(width: 44, child: Icon(Icons.chevron_right, size: 18)),
        ],
      ),
    );
  }
}

class _TeamDetailDialog extends StatefulWidget {
  final TeamModel team;
  final AdminRepository repo;
  const _TeamDetailDialog({required this.team, required this.repo});

  @override
  State<_TeamDetailDialog> createState() => _TeamDetailDialogState();
}

class _TeamDetailDialogState extends State<_TeamDetailDialog> {
  late final Future<({List<TeamMemberModel> members, List<MatchModel> matches})>
  _extra = _load();

  Future<({List<TeamMemberModel> members, List<MatchModel> matches})>
  _load() async {
    final members = await TeamRepository().fetchMembers(widget.team.id);
    final matches = await widget.repo.fetchMatchesForTeams([widget.team.id]);
    return (members: members, matches: matches);
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final hint = Theme.of(context).hintColor;
    final winRate = team.played == 0
        ? '–'
        : '${(team.wins * 100 / team.played).round()}%';
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
                    name: team.name,
                    imageUrl: team.logoUrl,
                    radius: 26,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          team.city ?? 'No city set',
                          style: TextStyle(color: hint),
                        ),
                      ],
                    ),
                  ),
                  LevelBadge(value: team.rating, size: 40, showLabel: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  _MiniStat(label: 'Record', value: team.record),
                  _MiniStat(label: 'Played', value: '${team.played}'),
                  _MiniStat(label: 'Win rate', value: winRate),
                  _MiniStat(label: 'Rating', value: '${team.rating}'),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: FutureBuilder<
                    ({List<TeamMemberModel> members, List<MatchModel> matches})
                  >(
                    future: _extra,
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      final members = data?.members;
                      TeamMemberModel? captain;
                      for (final m in members ?? const <TeamMemberModel>[]) {
                        if (m.isCaptain) captain = m;
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AdminDetailSection('Details'),
                          AdminInfoRow('City', team.city ?? 'Not set'),
                          AdminInfoRow(
                            'Captain',
                            captain == null
                                ? (members == null ? '…' : 'None')
                                : '${captain.name} (@${captain.username})',
                          ),
                          AdminInfoRow('Created', adminDate(team.createdAt)),
                          AdminInfoRow(
                            'Status',
                            team.isDisbanded
                                ? 'Disbanded ${adminDate(team.disbandedAt!)}'
                                : 'Active',
                          ),
                          AdminInfoRow(
                            'Matches counted',
                            '${team.played} (${team.wins} won, ${team.losses} lost, ${team.draws} drawn)',
                          ),
                          AdminInfoRow('Team ID', team.id),
                          AdminDetailSection(
                            members == null
                                ? 'Roster'
                                : 'Roster (${members.length})',
                          ),
                          if (snapshot.hasError)
                            Text(
                              'Could not load the roster and matches.',
                              style: TextStyle(color: hint),
                            )
                          else if (data == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            )
                          else ...[
                            if (data.members.isEmpty)
                              Text('No players yet.', style: TextStyle(color: hint)),
                            for (final m in data.members)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    GradientAvatar(
                                      name: m.name,
                                      imageUrl: m.avatarUrl,
                                      radius: 16,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            [
                                              '@${m.username}',
                                              m.roleLabel,
                                              if (m.position != null)
                                                m.position,
                                              'joined ${adminDate(m.joinedAt)}',
                                              'reliability ${m.reliability}%',
                                              'behaviour ${m.behaviorLabel}',
                                            ].join(' · '),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: hint),
                                          ),
                                        ],
                                      ),
                                    ),
                                    LevelBadge(value: m.elo, size: 26),
                                  ],
                                ),
                              ),
                            AdminDetailSection('Matches (${data.matches.length})'),
                            if (data.matches.isEmpty)
                              Text('No matches yet.', style: TextStyle(color: hint)),
                            for (final m in data.matches)
                              AdminMatchTile(match: m, myTeamIds: {team.id}),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: AdminPressScale(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
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
