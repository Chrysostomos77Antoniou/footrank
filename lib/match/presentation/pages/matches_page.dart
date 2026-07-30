import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/match/data/court_repository.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/court_model.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/match_status.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/team_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> with ThemeRepaintMixin {
  final _matchRepo = MatchRepository();
  final _teamRepo = TeamRepository();
  final _courtRepo = CourtRepository();

  TeamModel? _team; // the currently-selected team (when in several)
  List<TeamModel> _teams = [];
  bool _loadingTeam = true;
  Future<List<MatchRequestModel>>? _future;
  Future<List<MatchModel>>? _matchesFuture;
  Future<List<MatchRequestModel>>? _opponentsFuture;
  Future<Map<String, List<MatchProposalModel>>>? _proposalsFuture;
  Future<List<MatchProposalModel>>? _sentProposalsFuture;

  // Available Opponents filters -- city is mandatory (defaults to the acting
  // team's own registered city); everything else is optional narrowing.
  String? _filterCity;
  String? _filterCourtId;
  DateTime? _filterDate;
  TimeOfDay? _filterTime;
  String? _filterMatchType; // null = any, else 'casual' | 'ranked'
  List<CourtModel> _filterCourts = [];

  bool get _isCaptain =>
      _team != null &&
      _team!.captainId == SupabaseService.client.auth.currentUser?.id;

  // Upcoming Matches / Match History.
  int _matchesTab = 0;
  // Opponents / My Activity.
  int _mainTab = 0;
  // Open / Sent / Pending, inside My Activity.
  int _activityTab = 0;

  // One-time explainer for the Opponents vs My Activity split. Defaults to
  // "seen" so returning users never see a flash of it while prefs load;
  // flips to false (showing the banner) only once we've actually confirmed
  // it hasn't been dismissed before.
  bool _coachSeen = true;
  static const _coachKey = 'matches_page_tabs_coach_seen';

  @override
  void initState() {
    super.initState();
    _load();
    _loadCoachSeen();
    appRefresh.addListener(_load);
  }

  Future<void> _loadCoachSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_coachKey) ?? false;
      if (!mounted) return;
      setState(() => _coachSeen = seen);
    } catch (_) {
      // Best-effort persistence; ignore storage errors.
    }
  }

  Future<void> _dismissCoach() async {
    setState(() => _coachSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_coachKey, true);
    } catch (_) {
      // Best-effort persistence; ignore storage errors.
    }
  }

  @override
  void dispose() {
    appRefresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final teams = await _teamRepo.fetchMyTeams();
    if (!mounted) return;
    // Keep the current selection if it still exists, else default to the first.
    final previousTeamId = _team?.id;
    TeamModel? selected;
    if (_team != null) {
      final existing = teams.where((t) => t.id == _team!.id).toList();
      if (existing.isNotEmpty) selected = existing.first;
    }
    selected ??= teams.isEmpty ? null : teams.first;
    final sel = selected;
    setState(() {
      _teams = teams;
      _team = sel;
      _loadingTeam = false;
      if (sel != null && sel.id != previousTeamId) {
        _filterCity = canonicalCity(sel.city) ?? kCities.first;
        _filterCourtId = null;
        _filterDate = null;
        _filterTime = null;
        _filterMatchType = null;
        _filterCourts = [];
      }
      _future = sel == null ? null : _matchRepo.fetchMyTeamRequests(sel.id);
      _matchesFuture = sel == null ? null : _matchRepo.fetchTeamMatches(sel.id);
      _opponentsFuture = sel == null ? null : _fetchOpponents(sel.id);
      _proposalsFuture = sel == null || !_isCaptain
          ? null
          : _matchRepo.fetchProposalsForTeamRequests(sel.id);
      _sentProposalsFuture =
          sel == null ? null : _matchRepo.fetchSentProposals(sel.id);
    });
    if (sel != null && sel.id != previousTeamId) _loadFilterCourts();
  }

  void _selectTeam(TeamModel team) {
    if (team.id == _team?.id) return;
    setState(() {
      _team = team;
      _filterCity = canonicalCity(team.city) ?? kCities.first;
      _filterCourtId = null;
      _filterDate = null;
      _filterTime = null;
      _filterMatchType = null;
      _filterCourts = [];
      _future = _matchRepo.fetchMyTeamRequests(team.id);
      _matchesFuture = _matchRepo.fetchTeamMatches(team.id);
      _opponentsFuture = _fetchOpponents(team.id);
      _proposalsFuture = _isCaptain
          ? _matchRepo.fetchProposalsForTeamRequests(team.id)
          : null;
      _sentProposalsFuture = _matchRepo.fetchSentProposals(team.id);
    });
    _loadFilterCourts();
  }

  Future<List<MatchRequestModel>> _fetchOpponents(String teamId) {
    return _matchRepo.fetchCityRequests(
      city: _filterCity ?? kCities.first,
      excludeTeamId: teamId,
      courtId: _filterCourtId,
      date: _filterDate,
      timeOfDayMinutes:
          _filterTime == null ? null : _filterTime!.hour * 60 + _filterTime!.minute,
      matchType: _filterMatchType,
    );
  }

  Future<void> _loadFilterCourts() async {
    final city = _filterCity;
    if (city == null) return;
    final courts = await _courtRepo.fetchCourtsForCity(city);
    if (!mounted || city != _filterCity) return;
    setState(() => _filterCourts = courts);
  }

  void _setFilterCity(String city) {
    if (city == _filterCity) return;
    setState(() {
      _filterCity = city;
      _filterCourtId = null; // a court from the old city no longer applies
      _filterCourts = [];
      final team = _team;
      _opponentsFuture = team == null ? null : _fetchOpponents(team.id);
    });
    _loadFilterCourts();
  }

  void _setFilterCourt(String? courtId) {
    setState(() {
      _filterCourtId = courtId;
      final team = _team;
      _opponentsFuture = team == null ? null : _fetchOpponents(team.id);
    });
  }

  void _setFilterDate(DateTime? date) {
    setState(() {
      _filterDate = date;
      final team = _team;
      _opponentsFuture = team == null ? null : _fetchOpponents(team.id);
    });
  }

  void _setFilterTime(TimeOfDay? time) {
    setState(() {
      _filterTime = time;
      final team = _team;
      _opponentsFuture = team == null ? null : _fetchOpponents(team.id);
    });
  }

  void _setFilterMatchType(String? matchType) {
    setState(() {
      _filterMatchType = matchType;
      final team = _team;
      _opponentsFuture = team == null ? null : _fetchOpponents(team.id);
    });
  }

  void _reloadRequests() {
    final team = _team;
    if (team == null) return;
    setState(() {
      _future = _matchRepo.fetchMyTeamRequests(team.id);
      _matchesFuture = _matchRepo.fetchTeamMatches(team.id);
      _opponentsFuture = _fetchOpponents(team.id);
      _proposalsFuture = _isCaptain
          ? _matchRepo.fetchProposalsForTeamRequests(team.id)
          : null;
      _sentProposalsFuture = _matchRepo.fetchSentProposals(team.id);
    });
  }

  /// Any team member can propose the acting team against an open request
  /// (only accepting/rejecting is captain-only). Does not lock that request
  /// -- its own captain reviews all proposals and picks one, so more than
  /// one team may propose before that happens.
  Future<void> _propose(MatchRequestModel opponent) async {
    final team = _team;
    if (team == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Propose this match?'),
        content: Text(
            'Propose a match against ${opponent.teamName ?? 'this team'} in '
            '${opponent.city}. Their captain reviews proposals and picks '
            'one — you\'ll be notified either way.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Proposal')),
        ],
      ),
    );
    if (confirm != true) return;

    // Matches are 5-a-side -- fail fast with a clear message instead of
    // letting the request hit the server's "at least 5 players" check.
    final members = await _teamRepo.fetchMembers(team.id);
    if (!mounted) return;
    if (members.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${team.name} needs at least 5 players before you can propose a '
            'match (currently ${members.length}).',
          ),
        ),
      );
      return;
    }

    try {
      await _matchRepo.proposeMatch(requestId: opponent.id, teamId: team.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Proposal sent vs ${opponent.teamName}. Waiting for their '
                'captain to pick.')),
      );
      _reloadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _acceptProposal(MatchProposalModel proposal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept this proposal?'),
        content: Text(
            '${proposal.teamName ?? 'This team'} wants to play your match. '
            'Accepting confirms the match now and declines every other '
            'pending proposal on this request.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Accept')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _matchRepo.acceptProposal(proposal.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Match confirmed vs ${proposal.teamName ?? 'them'}!')),
      );
      _reloadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _rejectProposal(MatchProposalModel proposal) async {
    try {
      await _matchRepo.rejectProposal(proposal.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposal declined')),
      );
      _reloadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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

  Future<void> _rejectMatch(MatchModel m) async {
    final opponentName = m.homeTeamId == _team?.id
        ? (m.awayTeamName ?? 'the opponent')
        : (m.homeTeamName ?? 'the opponent');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this match?'),
        content: Text(
            'This removes the pending match against $opponentName for both '
            'teams. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _matchRepo.cancelMatch(m.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Match rejected')),
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
    // Ask which team to create the match for (only when in several).
    final team = await chooseTeam(context, _teams,
        title: 'Create a match for…');
    if (!mounted || team == null) return;
    // Keep the Matches view in sync with the team just chosen.
    _selectTeam(team);
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
          if (_team != null)
            TextButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Find Opponents'),
              onPressed: _openDiscovery,
            ),
        ],
      ),
      floatingActionButton: _teams.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Match'),
            )
          : null,
      body: AmbientBackground(child: SafeArea(child: _buildBody())),
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
          if (_teams.length > 1 && _team != null)
            FadeSlideIn(
              child: _TeamSelector(
                teams: _teams,
                selectedId: _team!.id,
                onSelect: _selectTeam,
              ),
            ),
          if (!_coachSeen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FadeSlideIn(
                child: _MatchesCoachBanner(onDismiss: _dismissCoach),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: FadeSlideIn(
              child: FutureBuilder<Map<String, List<MatchProposalModel>>>(
                future: _proposalsFuture,
                builder: (context, incomingSnap) {
                  final incomingCount = (incomingSnap.data ?? const {})
                      .values
                      .fold<int>(0, (sum, list) => sum + list.length);
                  return FutureBuilder<List<MatchModel>>(
                    future: _matchesFuture,
                    builder: (context, matchesSnap) {
                      final pendingCount = (matchesSnap.data ?? const [])
                          .where((m) => m.status == 'pending')
                          .length;
                      return _SectionTabs(
                        index: _mainTab,
                        items: [
                          const _TabItem(
                              Icons.person_search_outlined, 'Opponents'),
                          _TabItem(Icons.list_alt_outlined, 'My Activity',
                              badgeCount: incomingCount + pendingCount),
                        ],
                        onChanged: (i) => setState(() => _mainTab = i),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          IndexedStack(
            index: _mainTab,
            alignment: Alignment.topCenter,
            children: [
              // ---- Opponents: browse open requests from other teams ----
              Column(
                children: [
                  FadeSlideIn(
                    child: _OpponentFilters(
                      city: _filterCity ?? kCities.first,
                      courtId: _filterCourtId,
                      date: _filterDate,
                      time: _filterTime,
                      matchType: _filterMatchType,
                      courts: _filterCourts,
                      onCityChanged: _setFilterCity,
                      onCourtChanged: _setFilterCourt,
                      onDateChanged: _setFilterDate,
                      onTimeChanged: _setFilterTime,
                      onMatchTypeChanged: _setFilterMatchType,
                    ),
                  ),
                  FutureBuilder<List<MatchRequestModel>>(
                    future: _opponentsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const SkeletonList(count: 2);
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: ErrorView(
                            message: friendlyError(snapshot.error!),
                            onRetry: _reloadRequests,
                          ),
                        );
                      }
                      final opponents = snapshot.data ?? [];
                      if (opponents.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: EmptyView(
                            icon: Icons.person_search_outlined,
                            title: 'No open requests match your filters',
                            hint: 'Try a different court or date, or check '
                                'back later.',
                          ),
                        );
                      }
                      return Column(
                        children: opponents
                            .asMap()
                            .entries
                            .map((e) => FadeSlideIn(
                                  delay: Duration(milliseconds: 50 * e.key),
                                  child: _OpponentCard(
                                    opponent: e.value,
                                    onPropose: () => _propose(e.value),
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
              // ---- My Activity: everything about the acting team's own
              // requests and proposals, split Open / Sent / Awaiting Confirm
              // instead of separate top-level tabs ----
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: FutureBuilder<Map<String, List<MatchProposalModel>>>(
                      future: _proposalsFuture,
                      builder: (context, incomingSnap) {
                        final incomingCount = (incomingSnap.data ?? const {})
                            .values
                            .fold<int>(0, (sum, list) => sum + list.length);
                        return FutureBuilder<List<MatchModel>>(
                          future: _matchesFuture,
                          builder: (context, matchesSnap) {
                            final pendingCount = (matchesSnap.data ?? const [])
                                .where((m) => m.status == 'pending')
                                .length;
                            return _PillSubTabs(
                              index: _activityTab,
                              items: [
                                _PillItem('Open', badgeCount: incomingCount),
                                const _PillItem('Sent'),
                                _PillItem('Awaiting confirm',
                                    badgeCount: pendingCount),
                              ],
                              onChanged: (i) =>
                                  setState(() => _activityTab = i),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  IndexedStack(
                    index: _activityTab,
                    alignment: Alignment.topCenter,
                    children: [
                      FutureBuilder<List<MatchRequestModel>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SkeletonList(count: 2);
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: ErrorView(
                                message: friendlyError(snapshot.error!),
                                onRetry: _reloadRequests,
                              ),
                            );
                          }
                          final requests = snapshot.data
                                  ?.where((r) =>
                                      MatchStatus.fromString(r.status).isOpen)
                                  .toList() ??
                              [];
                          if (requests.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: EmptyView(
                                icon: Icons.sports_soccer_outlined,
                                title: 'No matches scheduled yet',
                                hint: 'Tap "Create Match" to start.',
                              ),
                            );
                          }
                          final uid = SupabaseService.client.auth.currentUser?.id;
                          return FutureBuilder<Map<String, List<MatchProposalModel>>>(
                            future: _proposalsFuture ??
                                Future.value(
                                    const <String, List<MatchProposalModel>>{}),
                            builder: (context, proposalsSnapshot) {
                              final proposalsByRequest =
                                  proposalsSnapshot.data ?? {};
                              return Column(
                                children: requests
                                    .asMap()
                                    .entries
                                    .map((e) => FadeSlideIn(
                                          delay:
                                              Duration(milliseconds: 50 * e.key),
                                          child: _RequestCard(
                                            request: e.value,
                                            onCancel: e.value.captainId == uid
                                                ? () => _cancelRequest(e.value)
                                                : null,
                                            proposals: _isCaptain
                                                ? proposalsByRequest[
                                                        e.value.id] ??
                                                    const []
                                                : const [],
                                            onAcceptProposal: _acceptProposal,
                                            onRejectProposal: _rejectProposal,
                                          ),
                                        ))
                                    .toList(),
                              );
                            },
                          );
                        },
                      ),
                      FutureBuilder<List<MatchProposalModel>>(
                        future: _sentProposalsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SkeletonList(count: 2);
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: ErrorView(
                                message: friendlyError(snapshot.error!),
                                onRetry: _reloadRequests,
                              ),
                            );
                          }
                          final sent = snapshot.data ?? [];
                          if (sent.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: EmptyView(
                                icon: Icons.outgoing_mail,
                                title: 'No open proposals',
                                hint:
                                    'Proposals your team sends to other teams\' '
                                    'requests show up here while they\'re pending.',
                              ),
                            );
                          }
                          return Column(
                            children: sent
                                .asMap()
                                .entries
                                .map((e) => FadeSlideIn(
                                      delay: Duration(milliseconds: 50 * e.key),
                                      child:
                                          _SentProposalCard(proposal: e.value),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                      FutureBuilder<List<MatchModel>>(
                        future: _matchesFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SkeletonList(count: 2);
                          }
                          final myTeamId = _team?.id;
                          final pending = (snapshot.data ?? [])
                              .where((m) => m.status == 'pending')
                              .toList();
                          if (pending.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: EmptyView(
                                icon: Icons.pending_actions_outlined,
                                title: 'Nothing waiting on confirmation',
                              ),
                            );
                          }
                          return Column(
                            children: pending.asMap().entries.map((e) {
                              final m = e.value;
                              final iAmHome = m.homeTeamId == myTeamId;
                              final iConfirmed =
                                  iAmHome ? m.homeOk : m.awayOk;
                              return FadeSlideIn(
                                delay: Duration(milliseconds: 50 * e.key),
                                child: _PendingMatchCard(
                                  match: m,
                                  iConfirmed: iConfirmed,
                                  canAct: _isCaptain,
                                  onConfirm: () => _confirmFixture(m),
                                  onReject: () => _rejectMatch(m),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          FutureBuilder<List<MatchModel>>(
            future: _matchesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList(count: 2);
              }
              final all = snapshot.data ?? [];
              final myTeamId = _team?.id;
              final upcoming =
                  all.where((m) => m.status == 'confirmed').toList();
              final history =
                  all.where((m) => m.status == 'completed').toList();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _SectionTabs(
                      index: _matchesTab,
                      items: [
                        _TabItem(Icons.event_available_outlined, 'Upcoming',
                            badgeCount: upcoming.length),
                        const _TabItem(Icons.history, 'History'),
                      ],
                      onChanged: (i) => setState(() => _matchesTab = i),
                    ),
                  ),
                  IndexedStack(
                    index: _matchesTab,
                    alignment: Alignment.topCenter,
                    children: [
                      if (upcoming.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: EmptyView(
                            icon: Icons.event_available_outlined,
                            title: 'No upcoming matches',
                          ),
                        )
                      else
                        Column(
                          children: upcoming
                              .asMap()
                              .entries
                              .map((e) => FadeSlideIn(
                                    delay: Duration(milliseconds: 50 * e.key),
                                    child: _MatchCard(
                                        match: e.value, myTeamId: myTeamId),
                                  ))
                              .toList(),
                        ),
                      if (history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: EmptyView(
                            icon: Icons.history,
                            title: 'No past matches yet',
                          ),
                        )
                      else
                        Column(
                          children: history
                              .asMap()
                              .entries
                              .map((e) => FadeSlideIn(
                                    delay: Duration(milliseconds: 50 * e.key),
                                    child: _MatchCard(
                                        match: e.value, myTeamId: myTeamId),
                                  ))
                              .toList(),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  final int badgeCount;
  const _TabItem(this.icon, this.label, {this.badgeCount = 0});
}

/// Icon + short-label tab bar for this page's two tab groups -- a plain
/// text GlassTabs row got unreadably cramped once "Open Requests" grew to
/// four segments, so each segment is now an icon over a one-word label
/// (scanned at a glance) with an optional badge for counts worth noticing
/// (incoming proposals on your requests, what you've sent, what's waiting
/// on a confirm).
class _SectionTabs extends StatelessWidget {
  final int index;
  final List<_TabItem> items;
  final ValueChanged<int> onChanged;

  const _SectionTabs({
    required this.index,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.iconAccent(context);
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return GlassCard(
      padding: const EdgeInsets.all(6),
      radius: 20,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: PressableScale(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  decoration: BoxDecoration(
                    color: index == i ? accent.withValues(alpha: 0.14) : null,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Badge(
                        isLabelVisible: items[i].badgeCount > 0,
                        label: Text('${items[i].badgeCount}'),
                        backgroundColor: AppColors.danger,
                        child: Icon(items[i].icon,
                            size: 20, color: index == i ? accent : muted),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: index == i ? accent : muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One-time explainer for the Opponents / My Activity split, shown until
/// dismissed (see [_MatchesPageState._dismissCoach]).
class _MatchesCoachBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _MatchesCoachBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.iconAccent(context);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Two places to look',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Opponents is for browsing and proposing matches. '
                  'My Activity tracks your own requests and proposals.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted(context)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Got it',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _PillItem {
  final String label;
  final int badgeCount;
  const _PillItem(this.label, {this.badgeCount = 0});
}

/// Lightweight sub-tab row (Open / Sent / Awaiting Confirm) nested inside
/// the My Activity tab -- plain pills, no icons, so they read as a step
/// below the primary Opponents/My Activity tab bar rather than competing
/// with it.
class _PillSubTabs extends StatelessWidget {
  final int index;
  final List<_PillItem> items;
  final ValueChanged<int> onChanged;

  const _PillSubTabs({
    required this.index,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.iconAccent(context);
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final border =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.16);
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: PressableScale(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: index == i ? accent.withValues(alpha: 0.14) : null,
                  border: index == i ? null : Border.all(color: border),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Text(
                      items[i].label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: index == i ? accent : muted,
                      ),
                    ),
                    if (items[i].badgeCount > 0)
                      Positioned(
                        right: 2,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${items[i].badgeCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Lets a multi-team user pick which team the Matches tab is acting as. The
/// selected team drives every section + Create Match, so the active team is
/// always explicit and nothing is created for the wrong team by accident.
class _TeamSelector extends StatelessWidget {
  final List<TeamModel> teams;
  final String selectedId;
  final ValueChanged<TeamModel> onSelect;
  const _TeamSelector(
      {required this.teams, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Acting as',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6))),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: teams
                .map((t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t.name),
                        selected: t.id == selectedId,
                        onSelected: (_) => onSelect(t),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        tint: accent,
        onTap: () => context.push(AppRoutes.matchDetail, extra: match.id),
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
  final List<MatchProposalModel> proposals;
  final ValueChanged<MatchProposalModel>? onAcceptProposal;
  final ValueChanged<MatchProposalModel>? onRejectProposal;
  const _RequestCard({
    required this.request,
    this.onCancel,
    this.proposals = const [],
    this.onAcceptProposal,
    this.onRejectProposal,
  });

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
    // Kick-off already passed: this request can never be matched now, so warn
    // the captain to cancel/recreate (the hourly cleanup also removes it soon).
    final passed = request.scheduledAt.isBefore(DateTime.now());
    final warn = Colors.orange.shade800;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  child: Text(request.format.split('v').first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${request.city} · ${request.format}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      if (passed) ...[
                        Text(_when,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 14, color: warn),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                  'Kick-off passed — cancel or recreate',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: warn)),
                            ),
                          ],
                        ),
                      ] else
                        Text(_when,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
            if (proposals.isNotEmpty) ...[
              const Divider(height: 20),
              Text('Proposals',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...proposals.map((p) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GradientAvatar(
                                name: p.teamName ?? '?',
                                imageUrl: p.teamLogo,
                                radius: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p.teamName ?? 'Unknown team',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: onRejectProposal == null
                                    ? null
                                    : () => onRejectProposal!(p),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: onAcceptProposal == null
                                    ? null
                                    : () => onAcceptProposal!(p),
                                child: const Text('Accept'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingMatchCard extends StatelessWidget {
  final MatchModel match;
  final bool iConfirmed;
  final bool canAct;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  const _PendingMatchCard({
    required this.match,
    required this.iConfirmed,
    required this.canAct,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final d = match.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        onTap: () => context.push(AppRoutes.matchDetail, extra: match.id),
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
            Text('${match.city} · $when · ${match.matchType}',
                style: Theme.of(context).textTheme.bodySmall),
            if (match.suggestedCourtName != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.iconAccent(context)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.place,
                          size: 18, color: AppColors.iconAccent(context)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(match.suggestedCourtName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.iconAccent(context))),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!canAct)
                  Expanded(
                    child: Text('Only your captain can confirm or reject',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.muted(context))),
                  )
                else if (iConfirmed)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('Waiting…',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.danger),
                    ),
                    onPressed: canAct ? onReject : null,
                    child: const Text('Reject'),
                  ),
                ),
                if (!iConfirmed) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: canAct ? onConfirm : null,
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
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
  final VoidCallback onPropose;
  const _OpponentCard({
    required this.opponent,
    required this.onPropose,
  });

  @override
  Widget build(BuildContext context) {
    final d = opponent.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GradientAvatar(
                  name: opponent.teamName ?? '?',
                  imageUrl: opponent.teamLogo,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(opponent.teamName ?? 'Unknown team',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                LevelBadge(value: opponent.teamRating ?? 0, size: 36),
              ],
            ),
            const SizedBox(height: 6),
            Text('${opponent.city} · $when · ${opponent.matchType}',
                style: Theme.of(context).textTheme.bodySmall),
            if (opponent.courtPicks != null &&
                opponent.courtPicks!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place, size: 17, color: AppColors.iconAccent(context)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      opponent.courtPicks!.map((c) => c.name).join(' · '),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.iconAccent(context)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPropose,
                child: const Text('Propose Match'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One proposal the acting team has sent, shown on the "Propose" tab so any
/// team member can see what's outstanding -- not just the person who sent
/// it. Read-only: only the target request's own captain can act on it.
class _SentProposalCard extends StatelessWidget {
  final MatchProposalModel proposal;
  const _SentProposalCard({required this.proposal});

  @override
  Widget build(BuildContext context) {
    final d = proposal.requestScheduledAt?.toLocal();
    final when = d == null
        ? null
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GradientAvatar(
              name: proposal.targetTeamName ?? '?',
              imageUrl: proposal.targetTeamLogo,
              radius: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(proposal.targetTeamName ?? 'Unknown team',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (proposal.requestCity != null) proposal.requestCity,
                      if (when != null) when,
                      if (proposal.requestMatchType != null)
                        proposal.requestMatchType,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (proposal.targetTeamRating != null)
              LevelBadge(value: proposal.targetTeamRating!, size: 36),
            const SizedBox(width: 8),
            _Chip(label: 'Pending', color: Theme.of(context).colorScheme.secondary),
          ],
        ),
      ),
    );
  }
}

/// City (mandatory) + court/date/time/match-type filters for the Available
/// Opponents list.
/// City defaults to the acting team's own registered city but can be
/// switched to browse other cities; court and date are optional narrowing —
/// clearing them is the only way to see "every open request in the city".
/// Collapsed by default behind a single "Filters" summary row -- expands to
/// reveal the full city/court/type/date/time grid. Keeps the Available
/// Opponents list from being pushed below the fold by five always-visible
/// fields when most of the time nobody's actively narrowing the search.
class _OpponentFilters extends StatefulWidget {
  final String city;
  final String? courtId;
  final DateTime? date;
  final TimeOfDay? time;
  final String? matchType;
  final List<CourtModel> courts;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String?> onCourtChanged;
  final ValueChanged<DateTime?> onDateChanged;
  final ValueChanged<TimeOfDay?> onTimeChanged;
  final ValueChanged<String?> onMatchTypeChanged;

  const _OpponentFilters({
    required this.city,
    required this.courtId,
    required this.date,
    required this.time,
    required this.matchType,
    required this.courts,
    required this.onCityChanged,
    required this.onCourtChanged,
    required this.onDateChanged,
    required this.onTimeChanged,
    required this.onMatchTypeChanged,
  });

  @override
  State<_OpponentFilters> createState() => _OpponentFiltersState();
}

class _OpponentFiltersState extends State<_OpponentFilters> {
  bool _expanded = false;

  String get city => widget.city;
  String? get courtId => widget.courtId;
  DateTime? get date => widget.date;
  TimeOfDay? get time => widget.time;
  String? get matchType => widget.matchType;
  List<CourtModel> get courts => widget.courts;
  ValueChanged<String> get onCityChanged => widget.onCityChanged;
  ValueChanged<String?> get onCourtChanged => widget.onCourtChanged;
  ValueChanged<DateTime?> get onDateChanged => widget.onDateChanged;
  ValueChanged<TimeOfDay?> get onTimeChanged => widget.onTimeChanged;
  ValueChanged<String?> get onMatchTypeChanged => widget.onMatchTypeChanged;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) onDateChanged(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: time ?? TimeOfDay.now(),
    );
    if (picked != null) onTimeChanged(picked);
  }

  String get _summary {
    final courtName = courtId == null
        ? 'Any court'
        : courts.firstWhere((c) => c.id == courtId,
                orElse: () => const CourtModel(id: '', name: 'Any court', city: ''))
            .name;
    final typeLabel = matchType == null
        ? 'Any type'
        : (matchType == 'ranked' ? 'Ranked' : 'Casual');
    final dateLabel = date == null ? 'Any date' : _formatDate(date!);
    return '$city · $courtName · $typeLabel · $dateLabel';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 18, color: AppColors.iconAccent(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _expanded ? 'Filters' : _summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: _buildFields(context),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFields(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: city,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'City',
              isDense: true,
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
            items: kCities
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (c) {
              if (c != null) onCityChanged(c);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: courtId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Court',
                    isDense: true,
                    prefixIcon: Icon(Icons.sports_soccer_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('Any court')),
                    ...courts.map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: onCourtChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: matchType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    isDense: true,
                    prefixIcon: Icon(Icons.emoji_events_outlined),
                  ),
                  items: const [
                    DropdownMenuItem<String>(
                        value: null, child: Text('Any type')),
                    DropdownMenuItem(value: 'casual', child: Text('Casual')),
                    DropdownMenuItem(value: 'ranked', child: Text('Ranked')),
                  ],
                  onChanged: onMatchTypeChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickDate(context),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date',
                      isDense: true,
                      prefixIcon: const Icon(Icons.event_outlined),
                      suffixIcon: date == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => onDateChanged(null),
                            ),
                    ),
                    child: Text(
                      date == null ? 'Any date' : _formatDate(date!),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickTime(context),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Time',
                      isDense: true,
                      prefixIcon: const Icon(Icons.access_time),
                      suffixIcon: time == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => onTimeChanged(null),
                            ),
                    ),
                    child: Text(
                      time == null ? 'Any time' : time!.format(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
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
