import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

class _MatchesPageState extends State<MatchesPage> {
  final _matchRepo = MatchRepository();
  final _teamRepo = TeamRepository();

  TeamModel? _team;
  bool _isCaptain = false;
  bool _loadingTeam = true;
  Future<List<MatchRequestModel>>? _future;
  Future<List<MatchModel>>? _matchesFuture;

  @override
  void initState() {
    super.initState();
    _load();
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
    });
  }

  void _reloadRequests() {
    final team = _team;
    if (team == null) return;
    setState(() {
      _future = _matchRepo.fetchMyTeamRequests(team.id);
      _matchesFuture = _matchRepo.fetchTeamMatches(team.id);
    });
  }

  Future<void> _openCreate() async {
    final team = _team;
    if (team == null) return;
    final created = await context.push<bool>(
      AppRoutes.createMatch,
      extra: team.id,
    );
    if (created == true) _reloadRequests();
  }

  void _openDiscovery() {
    final team = _team;
    if (team == null) return;
    context.push(AppRoutes.discoverMatches, extra: team.id);
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_team == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Join or create a team to organise matches.',
            textAlign: TextAlign.center,
          ),
        ),
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
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
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
                children:
                    requests.map((r) => _RequestCard(request: r)).toList(),
              );
            },
          ),
          _SectionHeader(title: 'Confirmed Matches'),
          FutureBuilder<List<MatchModel>>(
            future: _matchesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final matches = snapshot.data ?? [];
              if (matches.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('No confirmed matches yet.'),
                );
              }
              return Column(
                children:
                    matches.map((m) => _MatchCard(match: m)).toList(),
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
  const _MatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final d = match.scheduledAt;
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final score = (match.homeScore != null && match.awayScore != null)
        ? '${match.homeScore} - ${match.awayScore}'
        : 'vs';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        onTap: () => context.push(AppRoutes.matchDetail, extra: match.id),
        title: Text(
          '${match.homeTeamName ?? 'Home'}  $score  ${match.awayTeamName ?? 'Away'}',
        ),
        subtitle: Text('${match.city} · $when · ${match.matchType}'),
        trailing: Text(
          MatchStatus.fromString(match.status).label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final MatchRequestModel request;
  const _RequestCard({required this.request});

  String get _when {
    final d = request.scheduledAt;
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
        trailing: Column(
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
