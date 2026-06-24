import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/match_status.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> with ThemeRepaintMixin {
  final _matchRepo = MatchRepository();
  final _teamRepo = TeamRepository();

  TeamModel? _team;
  bool _isCaptain = false;
  bool _loadingTeam = true;
  Future<List<MatchRequestModel>>? _future;
  Future<List<MatchModel>>? _matchesFuture;
  Future<List<MatchRequestModel>>? _opponentsFuture;

  @override
  void initState() {
    super.initState();
    _load();
    appRefresh.addListener(_load);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final team = await _teamRepo.fetchMyTeam();
    final uid = SupabaseService.client.auth.currentUser?.id;
    if (!mounted) return;
    setState(() {
      _team = team;
      _isCaptain = team != null && team.captainId == uid;
      _loadingTeam = false;
      _future =
          team == null ? null : _matchRepo.fetchMyTeamRequests(team.id);
      _matchesFuture =
          team == null ? null : _matchRepo.fetchTeamMatches(team.id);
      _opponentsFuture =
          team == null ? null : _matchRepo.findAllOpponents(team.id);
    });
  }

  void _reloadRequests() {
    final team = _team;
    if (team == null) return;
    setState(() {
      _future = _matchRepo.fetchMyTeamRequests(team.id);
      _matchesFuture = _matchRepo.fetchTeamMatches(team.id);
      _opponentsFuture = _matchRepo.findAllOpponents(team.id);
    });
  }

  Future<void> _accept(MatchRequestModel opponent) async {
    final team = _team;
    if (team == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request this match?'),
        content: Text(
            'Propose a match against ${opponent.teamName ?? 'this team'} in '
            '${opponent.city}. It becomes confirmed once their captain also '
            'confirms.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Request')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _matchRepo.acceptMatchRequest(
          requestId: opponent.id, awayTeamId: team.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Match requested vs ${opponent.teamName}. Waiting for their '
                'captain to confirm.')),
      );
      _reloadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _confirmFixture(MatchModel m) async {
    try {
      final status = await _matchRepo.confirmFixture(m.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(status == 'confirmed'
                ? 'Match confirmed!'
                : 'Confirmed on your side. Waiting for the opponent.')),
      );
      _reloadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openCreate() async {
    final team = _team;
    if (team == null) return;
    final created = await context.push<bool>(
      AppRoutes.createMatch,
      extra: team.id,
    );
    if (created == true) {
      _reloadRequests();
      if (!mounted) return;
      final findNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request created'),
          content: const Text(
              'Find an opponent now? We\'ll show nearby teams looking for a '
              'match at a similar time and rating.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Find Opponents'),
            ),
          ],
        ),
      );
      if (findNow == true) _openDiscovery();
    }
  }

  Future<void> _cancelRequest(MatchRequestModel r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel match request?'),
        content: Text(
            'This will remove your open request for ${r.city}. '
            'You can create a new one anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _matchRepo.deleteRequest(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Match request cancelled')),
      );
      _reloadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openDiscovery() async {
    final team = _team;
    if (team == null) return;
    await context.push(AppRoutes.discoverMatches, extra: team.id);
    _reloadRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        actions: [
          if (_isCaptain)
            TextButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Find Opponents'),
              onPressed: _openDiscovery,
            ),
        ],
      ),
      floatingActionButton: _isCaptain
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Match'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingTeam) {
      return const LoadingView();
    }
    if (_team == null) {
      return const EmptyView(
        icon: Icons.groups_outlined,
        title: 'No team yet',
        hint: 'Join or create a team to organise matches.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _reloadRequests(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _SectionHeader(title: 'Open Requests'),
          FutureBuilder<List<MatchRequestModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList(count: 2);
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: ${snapshot.error}'),
                );
              }
              final requests = snapshot.data
                      ?.where((r) =>
                          MatchStatus.fromString(r.status).isOpen)
                      .toList() ??
                  [];
              if (requests.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text(_isCaptain
                      ? 'No open requests. Tap "Create Match" to start.'
                      : 'No open requests.'),
                );
              }
              return Column(
                children: requests
                    .map((r) => _RequestCard(
                          request: r,
                          onCancel: _isCaptain ? () => _cancelRequest(r) : null,
                        ))
                    .toList(),
              );
            },
          ),
          if (_isCaptain) ...[
            _SectionHeader(title: 'Available Opponents'),
            FutureBuilder<List<MatchRequestModel>>(
              future: _opponentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SkeletonList(count: 2);
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading opponents: ${snapshot.error}'),
                  );
                }
                final opponents = snapshot.data ?? [];
                if (opponents.isEmpty) {
                  return const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                        'No matching opponents yet. Opponents appear when '
                        'another team has an open request in the same city, '
                        'on the same date (±30 min), with a similar rating.'),
                  );
                }
                return Column(
                  children: opponents
                      .map((o) => _OpponentCard(
                            opponent: o,
                            onAccept: () => _accept(o),
                          ))
                      .toList(),
                );
              },
            ),
          ],
          FutureBuilder<List<MatchModel>>(
            future: _matchesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList(count: 2);
              }
              final all = snapshot.data ?? [];
              final myTeamId = _team?.id;
              final pending =
                  all.where((m) => m.status == 'pending').toList();
              final upcoming =
                  all.where((m) => m.status == 'confirmed').toList();
              final history =
                  all.where((m) => m.status == 'completed').toList();
              return Column(
                children: [
                  if (pending.isNotEmpty) ...[
                    _SectionHeader(title: 'Pending Confirmation'),
                    ...pending.map((m) {
                      final iAmHome = m.homeTeamId == myTeamId;
                      final iConfirmed = iAmHome ? m.homeOk : m.awayOk;
                      return _PendingMatchCard(
                        match: m,
                        iConfirmed: iConfirmed,
                        onConfirm: () => _confirmFixture(m),
                      );
                    }),
                  ],
                  _SectionHeader(title: 'Upcoming Matches'),
                  if (upcoming.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('No upcoming matches.'),
                    )
                  else
                    ...upcoming.map((m) => _MatchCard(match: m, myTeamId: myTeamId)),
                  _SectionHeader(title: 'Match History'),
                  if (history.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('No past matches yet.'),
                    )
                  else
                    ...history.map((m) => _MatchCard(match: m, myTeamId: myTeamId)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final MatchModel match;
  final String? myTeamId;
  const _MatchCard({required this.match, this.myTeamId});

  /// 'win' | 'loss' | 'draw' for my team, or null if not a finished match.
  String? get _result {
    if (match.status != 'completed' ||
        match.homeScore == null ||
        match.awayScore == null ||
        myTeamId == null) {
      return null;
    }
    final iAmHome = match.homeTeamId == myTeamId;
    final mine = iAmHome ? match.homeScore! : match.awayScore!;
    final theirs = iAmHome ? match.awayScore! : match.homeScore!;
    if (mine > theirs) return 'win';
    if (mine < theirs) return 'loss';
    return 'draw';
  }

  @override
  Widget build(BuildContext context) {
    final d = match.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final center = (match.homeScore != null && match.awayScore != null)
        ? '${match.homeScore} - ${match.awayScore}'
        : 'vs';
    final result = _result;
    final (Color? accent, String? label) = switch (result) {
      'win' => (AppColors.success, 'WON'),
      'loss' => (AppColors.danger, 'LOST'),
      'draw' => (AppColors.silver, 'DRAW'),
      _ => (null, null),
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: accent?.withValues(alpha: 0.16),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(AppRoutes.matchDetail, extra: match.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TeamMini(
                      name: match.homeTeamName ?? 'Home',
                      logo: match.homeTeamLogo,
                      rating: match.homeTeamRating,
                      record: match.homeTeamRecord,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(center,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                  Expanded(
                    child: _TeamMini(
                      name: match.awayTeamName ?? 'Away',
                      logo: match.awayTeamLogo,
                      rating: match.awayTeamRating,
                      record: match.awayTeamRecord,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('${match.city} · $when · ${match.matchType}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  if (label != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent!.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 12)),
                    )
                  else
                    Text(MatchStatus.fromString(match.status).label,
                        style: Theme.of(context).textTheme.labelLarge),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact team identity: logo + name + ELO chip. Used in match cards.
class _TeamMini extends StatelessWidget {
  final String name;
  final String? logo;
  final int? rating;
  final String? record;
  final bool alignEnd;
  const _TeamMini({
    required this.name,
    this.logo,
    this.rating,
    this.record,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = GradientAvatar(name: name, imageUrl: logo, radius: 18);
    final texts = Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        LevelBadge(value: rating ?? 0, size: 32),
        if (record != null) ...[
          const SizedBox(height: 3),
          Text(record!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ],
    );
    final children = alignEnd
        ? [Expanded(child: texts), const SizedBox(width: 8), avatar]
        : [avatar, const SizedBox(width: 8), Expanded(child: texts)];
    return Row(children: children);
  }
}

class _RequestCard extends StatelessWidget {
  final MatchRequestModel request;
  final VoidCallback? onCancel;
  const _RequestCard({required this.request, this.onCancel});

  String get _when {
    final d = request.scheduledAt.toLocal();
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(request.format.split('v').first),
        ),
        title: Text('${request.city} · ${request.format}'),
        subtitle: Text(_when),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Chip(
                  label: request.matchType,
                  color: request.isRanked
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: 4),
                Text(MatchStatus.fromString(request.status).label,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (onCancel != null)
              IconButton(
                tooltip: 'Cancel request',
                icon: const Icon(Icons.delete_outline),
                color: Theme.of(context).colorScheme.error,
                onPressed: onCancel,
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingMatchCard extends StatelessWidget {
  final MatchModel match;
  final bool iConfirmed;
  final VoidCallback onConfirm;
  const _PendingMatchCard({
    required this.match,
    required this.iConfirmed,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final d = match.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _TeamMini(
                    name: match.homeTeamName ?? 'Home',
                    logo: match.homeTeamLogo,
                    rating: match.homeTeamRating,
                      record: match.homeTeamRecord,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('vs',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                Expanded(
                  child: _TeamMini(
                    name: match.awayTeamName ?? 'Away',
                    logo: match.awayTeamLogo,
                    rating: match.awayTeamRating,
                      record: match.awayTeamRecord,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('${match.city} · $when · ${match.matchType}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                iConfirmed
                    ? Text('Waiting…',
                        style: Theme.of(context).textTheme.bodySmall)
                    : SizedBox(
                        height: 36,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: onConfirm,
                          child: const Text('Confirm'),
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

class _OpponentCard extends StatelessWidget {
  final MatchRequestModel opponent;
  final VoidCallback onAccept;
  const _OpponentCard({required this.opponent, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final d = opponent.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: GradientAvatar(
          name: opponent.teamName ?? '?',
          imageUrl: opponent.teamLogo,
          radius: 22,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(opponent.teamName ?? 'Unknown team',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            LevelBadge(value: opponent.teamRating ?? 0, size: 36),
          ],
        ),
        subtitle: Text('${opponent.city} · $when · ${opponent.matchType}'),
        trailing: SizedBox(
          height: 38,
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: onAccept,
            child: const Text('Confirm'),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
