import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/utils/reloadable.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/pitch_power_preview.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/core/widgets/segmented_tabs.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/match/presentation/widgets/match_cards.dart';
import 'package:footrank/match/presentation/widgets/opponent_filters.dart';
import 'package:footrank/match/presentation/widgets/roster_picker.dart';
import 'package:footrank/match/presentation/widgets/team_switcher.dart';
import 'package:footrank/match/presentation/widgets/venue_widgets.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/match_status.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/payment/data/payment_repository.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/team_picker.dart';
import 'package:url_launcher/url_launcher.dart';

// The cards used to be defined in this file. Other code (and the tests) still
// reach them through it, so it keeps handing them out.
export 'package:footrank/match/presentation/widgets/match_cards.dart'
    show RequestCard, SentProposalCard;

/// The Matches screen.
///
/// Three tabs, one question each:
///  * Opponents -- who can we play? (other teams' open requests, with filters)
///  * Activity  -- what is in motion? (our requests and the proposals on them,
///                 proposals we sent, matches waiting for both captains)
///  * Matches   -- what is booked and what is done? (upcoming / history)
///
/// This class fetches and acts; how things look is in the widgets it uses.
class MatchesPage extends StatefulWidget {
  const MatchesPage({
    super.key,
    this.matchRepository,
    this.teamRepository,
    this.paymentRepository,
    this.currentUserId,
    this.pitchPowerLoader,
  });

  /// Test seams. Production leaves all five null and gets the real
  /// repositories, the signed-in user and the server's Pitch Power preview.
  @visibleForTesting
  final MatchRepository? matchRepository;
  @visibleForTesting
  final TeamRepository? teamRepository;
  @visibleForTesting
  final PaymentRepository? paymentRepository;
  @visibleForTesting
  final String? currentUserId;
  @visibleForTesting
  final PitchPowerLoader? pitchPowerLoader;

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> with ThemeRepaintMixin {
  late final MatchRepository _matchRepo =
      widget.matchRepository ?? MatchRepository();
  late final TeamRepository _teamRepo =
      widget.teamRepository ?? TeamRepository();
  late final PaymentRepository _paymentRepo =
      widget.paymentRepository ?? PaymentRepository();

  String? get _userId =>
      widget.currentUserId ?? SupabaseService.client.auth.currentUser?.id;

  // ---- who we are acting as ------------------------------------------------

  TeamModel? _team; // the currently-selected team (when in several)
  List<TeamModel> _teams = [];
  bool _loadingTeam = true;
  Object? _teamsError;

  // Member count of the selected team, used to steer under-staffed captains
  // toward posting a request instead of proposing (see _loadMemberCount).
  int? _memberCount;

  // ---- what the tabs show --------------------------------------------------
  // Each list keeps its last answer while a newer one loads (see Reloadable),
  // so refreshing never blanks the screen and switching tabs never reloads.

  final _requests = Reloadable<List<MatchRequestModel>>();
  final _matches = Reloadable<List<MatchModel>>();
  final _opponents = Reloadable<List<MatchRequestModel>>();
  final _incoming = Reloadable<Map<String, List<MatchProposalModel>>>();
  final _sent = Reloadable<List<MatchProposalModel>>();

  List<Reloadable<Object>> get _loads =>
      [_requests, _matches, _opponents, _incoming, _sent];

  // Available Opponents filters -- city is mandatory (defaults to the acting
  // team's own registered city); everything else is optional narrowing.
  String? _filterCity;
  DateTime? _filterDate;
  TimeOfDay? _filterTime;
  String? _filterMatchType; // null = any, else 'casual' | 'ranked'
  // 0 = any Pitch Power -- the app no longer restricts which opponents are
  // visible; a captain who wants to narrow by strength sets this themselves.
  int _filterPowerRange = 0;

  /// Fees this captain still owes, keyed by match id. Drives the Pay button on
  /// each upcoming match card, so settling up never requires opening the match.
  /// Only ever populated for teams the signed-in user captains, which is what
  /// makes the button safe to show: if there is an entry, this user can pay it.
  Map<String, PendingFee> _pendingFees = const {};

  // ---- which view of it ----------------------------------------------------

  int _mainTab = 0; // Opponents / Activity / Matches
  int _activityTab = 0; // Requests / Sent / To confirm
  int _matchesTab = 0; // Upcoming / History

  // One controller per tab: the three lists sit side by side in an
  // IndexedStack and must not share the primary scroll controller.
  final _opponentsScroll = ScrollController();
  final _activityScroll = ScrollController();
  final _matchesScroll = ScrollController();

  bool get _isCaptain {
    final uid = _userId;
    return uid != null && _team?.captainId == uid;
  }

  String get _defaultCity => canonicalCity(_team?.city) ?? kCities.first;

  bool get _filtersActive =>
      (_filterCity ?? _defaultCity) != _defaultCity ||
      _filterDate != null ||
      _filterTime != null ||
      _filterMatchType != null ||
      _filterPowerRange != 0;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadPendingFees();
    appRefresh.addListener(_load);
    appRefresh.addListener(_loadPendingFees);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_load);
    appRefresh.removeListener(_loadPendingFees);
    _opponentsScroll.dispose();
    _activityScroll.dispose();
    _matchesScroll.dispose();
    super.dispose();
  }

  Future<void> _loadPendingFees() async {
    final fees = await _paymentRepo.fetchPendingFees();
    if (!mounted) return;
    setState(() => _pendingFees = {for (final f in fees) f.matchId: f});
  }

  /// Loads the user's teams, then everything for the selected one. Completes
  /// when all of it has landed, so pull-to-refresh can wait for it.
  Future<void> _load() async {
    final List<TeamModel> teams;
    try {
      teams = await _teamRepo.fetchMyTeams();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTeam = false;
        _teamsError = e;
      });
      return;
    }
    if (!mounted) return;
    // Keep the current selection if it still exists, else default to the first.
    final previousTeamId = _team?.id;
    TeamModel? selected;
    if (_team != null) {
      selected = teams.where((t) => t.id == _team!.id).firstOrNull;
    }
    selected ??= teams.isEmpty ? null : teams.first;
    final teamChanged = selected?.id != previousTeamId;
    setState(() {
      _teams = teams;
      _team = selected;
      _loadingTeam = false;
      _teamsError = null;
      if (teamChanged) {
        _resetFilterValues(selected);
        _memberCount = null;
      }
    });
    if (teamChanged) {
      for (final l in _loads) {
        l.clear();
      }
    }
    final team = selected;
    if (team == null) return;
    await Future.wait([_reloadAll(), _loadMemberCount(team.id)]);
  }

  Future<void> _loadMemberCount(String teamId) async {
    try {
      final members = await _teamRepo.fetchMembers(teamId);
      if (!mounted || teamId != _team?.id) return;
      setState(() => _memberCount = members.length);
    } catch (_) {
      // Only steers the wording of an empty state; the default copy is fine.
    }
  }

  void _selectTeam(TeamModel team) {
    if (team.id == _team?.id) return;
    setState(() {
      _team = team;
      _resetFilterValues(team);
      _memberCount = null;
    });
    for (final l in _loads) {
      l.clear();
    }
    _reloadAll();
    _loadMemberCount(team.id);
  }

  /// Everything a tab shows, fetched again. Whatever is on screen stays until
  /// the new answer replaces it.
  Future<void> _reloadAll() {
    final team = _team;
    if (team == null) return Future.value();
    return Future.wait([
      _requests.reload(
          () => _matchRepo.fetchMyTeamRequests(team.id), _changed),
      _matches.reload(() => _matchRepo.fetchTeamMatches(team.id), _changed),
      _opponents.reload(() => _fetchOpponents(team.id), _changed),
      _incoming.reload(
        () => _isCaptain
            ? _matchRepo.fetchProposalsForTeamRequests(team.id)
            : Future.value(const <String, List<MatchProposalModel>>{}),
        _changed,
      ),
      _sent.reload(() => _matchRepo.fetchSentProposals(team.id), _changed),
    ]);
  }

  /// Pull-to-refresh: the spinner stays until everything has really reloaded,
  /// and a failure is said out loud instead of leaving stale data in silence.
  Future<void> _refresh() async {
    Object? failure;
    try {
      await Future.wait([_load(), _loadPendingFees()]);
    } catch (e) {
      failure = e;
    }
    failure ??= _teamsError ??
        _loads.map((l) => l.error).whereType<Object>().firstOrNull;
    if (failure != null && mounted) showError(context, failure);
  }

  Future<List<MatchRequestModel>> _fetchOpponents(String teamId) {
    final time = _filterTime;
    return _matchRepo.fetchCityRequests(
      city: _filterCity ?? _defaultCity,
      excludeTeamId: teamId,
      date: _filterDate,
      timeOfDayMinutes: time == null ? null : time.hour * 60 + time.minute,
      matchType: _filterMatchType,
    );
  }

  Future<void> _reloadOpponents() {
    final team = _team;
    if (team == null) return Future.value();
    // A different set of teams, not a newer version of the same one: drop the
    // old list so it is never shown under the new filter.
    _opponents.clear();
    return _opponents.reload(() => _fetchOpponents(team.id), _changed);
  }

  void _resetFilterValues(TeamModel? team) {
    _filterCity = canonicalCity(team?.city) ?? kCities.first;
    _filterDate = null;
    _filterTime = null;
    _filterMatchType = null;
    _filterPowerRange = 0;
  }

  void _setFilterCity(String city) {
    if (city == _filterCity) return;
    setState(() => _filterCity = city);
    _reloadOpponents();
  }

  void _setFilterDate(DateTime? date) {
    setState(() => _filterDate = date);
    _reloadOpponents();
  }

  void _setFilterTime(TimeOfDay? time) {
    setState(() => _filterTime = time);
    _reloadOpponents();
  }

  void _setFilterMatchType(String? matchType) {
    setState(() => _filterMatchType = matchType);
    _reloadOpponents();
  }

  /// Narrows the list already on screen; there is nothing to fetch.
  void _setFilterPowerRange(int range) {
    setState(() => _filterPowerRange = range);
  }

  void _resetFilters() {
    setState(() => _resetFilterValues(_team));
    _reloadOpponents();
  }

  // ---- actions ---------------------------------------------------------------

  /// Any team member can propose the acting team against an open request
  /// (only accepting/rejecting is captain-only). Does not lock that request
  /// -- its own captain reviews all proposals and picks one, so more than
  /// one team may propose before that happens.
  Future<void> _propose(MatchRequestModel opponent) async {
    final team = _team;
    if (team == null) return;
    // Besides confirming, the member may type a venue they would rather play
    // at; their captain can accept it or decline (see the proposal card). The
    // dialog also says what the match is worth against THIS opponent.
    final choice = await showProposeDialog(
      context,
      opponentName: opponent.teamName ?? 'this team',
      city: opponent.city,
      requestVenue: opponent.venueText,
      stakes: PitchPowerPreview(
        teamId: team.id,
        opponentTeamId: opponent.teamId,
        matchType: opponent.matchType,
        compact: true,
        loader: widget.pitchPowerLoader,
      ),
    );
    if (choice == null || !mounted) return;

    // Matches are 5-a-side -- fail fast with a clear message instead of
    // letting the request hit the server's "at least 5 players" check.
    final members = await _teamRepo.fetchMembers(team.id);
    if (!mounted) return;
    if (members.length < 5) {
      showError(
        context,
        '${team.name} needs at least 5 players before you can propose a '
        'match (currently ${members.length}).',
      );
      return;
    }

    // Captain / vice-captain choose who is playing. Other members propose
    // with the whole team on the roster (they can edit it afterwards).
    final uid = _userId;
    final me = members.where((m) => m.userId == uid).firstOrNull;
    List<String>? roster;
    if (me != null && (me.isCaptain || me.isViceCaptain)) {
      roster = await showRosterSheet(
        context,
        members: members,
        title: 'Who is playing for ${team.name}?',
        confirmLabel: 'Send Proposal',
      );
      if (roster == null || !mounted) return;
    }

    try {
      await _matchRepo.proposeMatch(
        requestId: opponent.id,
        teamId: team.id,
        rosterUserIds: roster,
        venueText: choice.venueText,
        venueLocation: choice.location,
      );
      if (!mounted) return;
      showSuccess(
        context,
        'Proposal sent vs ${opponent.teamName}. Waiting for their captain to '
        'pick.',
      );
      _reloadAll();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _acceptProposal(
    MatchProposalModel proposal,
    MatchRequestModel request,
  ) async {
    final confirm = await showAcceptProposalDialog(
      context,
      teamName: proposal.teamName ?? 'This team',
      venueText: proposal.venueText,
      stakes: PitchPowerPreview(
        teamId: request.teamId,
        opponentTeamId: proposal.proposingTeamId,
        matchType: request.matchType,
        compact: true,
        loader: widget.pitchPowerLoader,
      ),
    );
    if (confirm != true) return;
    try {
      await _matchRepo.acceptProposal(proposal.id);
      if (!mounted) return;
      showSuccess(
          context, 'Match confirmed vs ${proposal.teamName ?? 'them'}!');
      _reloadAll();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rejectProposal(MatchProposalModel proposal) async {
    try {
      await _matchRepo.rejectProposal(proposal.id);
      if (!mounted) return;
      showSuccess(context, 'Proposal declined');
      _reloadAll();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _confirmFixture(MatchModel m) async {
    try {
      final status = await _matchRepo.confirmFixture(m.id);
      if (!mounted) return;
      showSuccess(
        context,
        status == 'confirmed'
            ? 'Match confirmed!'
            : 'Confirmed on your side. Waiting for the opponent.',
      );
      _reloadAll();
    } catch (e) {
      if (mounted) showError(context, e);
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
      showSuccess(context, 'Match rejected');
      _reloadAll();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openCreate() async {
    // Ask which team to create the match for (only when in several).
    final team =
        await chooseTeam(context, _teams, title: 'Create a match for…');
    if (!mounted || team == null) return;
    // Keep the Matches view in sync with the team just chosen.
    _selectTeam(team);
    // Then choose who is playing (same style of picker as the team choice).
    final members = await _teamRepo.fetchMembers(team.id);
    if (!mounted) return;
    if (members.length < 5) {
      showError(
        context,
        '${team.name} needs at least 5 players before you can create a '
        'match (currently ${members.length}).',
      );
      return;
    }
    final roster = await showRosterSheet(
      context,
      members: members,
      title: 'Who is playing for ${team.name}?',
      confirmLabel: 'Continue',
    );
    if (!mounted || roster == null) return;
    final created = await context.push<MatchRequestModel>(
      AppRoutes.createMatch,
      extra: CreateMatchArgs(team.id, roster),
    );
    if (created != null) {
      _reloadAll();
      if (!mounted) return;
      final invite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request created'),
          content: const Text(
              'Invite a rival team now? Share your match details so another '
              'team can find and propose against your request.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Invite a Rival Team'),
            ),
          ],
        ),
      );
      if (invite == true) _inviteRival(created);
    }
  }

  Future<void> _cancelRequest(MatchRequestModel r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel match request?'),
        content: Text('This will remove your open request for ${r.city}. '
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
      showSuccess(context, 'Match request cancelled');
      _reloadAll();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Shares [request]'s details via WhatsApp so a captain can invite a rival
  /// team directly instead of only waiting for one to browse and propose.
  Future<void> _inviteRival(MatchRequestModel request) async {
    final d = request.scheduledAt.toLocal();
    final date = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')} at '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    final msg = "Hey! We're looking for a match in ${request.city} on $date. "
        "Got a team? Let's set one up on FootRank!";
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showError(context, 'Could not open WhatsApp');
    }
  }

  // ---- build -----------------------------------------------------------------

  /// Room at the bottom of every list so the last card is never hidden behind
  /// the Create Match button.
  static const double _fabClearance = AppSpacing.xxxl * 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Matches',
          style: TextStyle(fontSize: 26, letterSpacing: -0.26),
        ),
      ),
      floatingActionButton:
          _teams.isEmpty ? null : _CreateMatchButton(onPressed: _openCreate),
      body: AmbientBackground(child: SafeArea(child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_loadingTeam) return const LoadingView();
    final team = _team;
    if (team == null) {
      if (_teamsError != null) {
        return ErrorView(message: friendlyError(_teamsError!), onRetry: _load);
      }
      return const EmptyView(
        icon: Icons.groups_outlined,
        title: 'No team yet',
        hint: 'Join or create a team to organise matches.',
      );
    }

    final Map<String, List<MatchProposalModel>> proposalsByRequest =
        _incoming.data ?? const {};
    final incoming =
        proposalsByRequest.values.fold<int>(0, (sum, list) => sum + list.length);
    final matches = _matches.data ?? const <MatchModel>[];
    // Only a captain can act on a match waiting for confirmation, so only a
    // captain is nudged about it.
    final toConfirm =
        _isCaptain ? matches.where((m) => m.status == 'pending').length : 0;
    final feesDue = matches
        .where((m) => m.status == 'confirmed' && _pendingFees.containsKey(m.id))
        .length;

    final tabs = [
      _buildOpponentsTab(team),
      _buildActivityTab(team, incoming: incoming, toConfirm: toConfirm),
      _buildMatchesTab(team),
    ];
    return Column(
      children: [
        if (_teams.length > 1)
          TeamSwitcher(
            teams: _teams,
            selectedId: team.id,
            onSelect: _selectTeam,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSemantic.screenPadding,
            vertical: AppSpacing.xs,
          ),
          child: SegmentedTabs(
            index: _mainTab,
            items: [
              const SegmentedTabItem('Opponents'),
              SegmentedTabItem('Activity', badgeCount: incoming + toConfirm),
              SegmentedTabItem('Matches', badgeCount: feesDue),
            ],
            onChanged: (i) => setState(() => _mainTab = i),
          ),
        ),
        // All three tabs stay built, so each keeps its scroll position, its
        // filters and its data while you look at another one. The ones out of
        // sight do not tick (no shimmer running behind your back).
        Expanded(
          child: IndexedStack(
            index: _mainTab,
            sizing: StackFit.expand,
            children: [
              for (var i = 0; i < tabs.length; i++)
                TickerMode(enabled: i == _mainTab, child: tabs[i]),
            ],
          ),
        ),
      ],
    );
  }

  /// One tab: a list you can pull down to refresh, with its own scroll
  /// position.
  Widget _tab({
    required ScrollController controller,
    required List<Widget> children,
  }) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          top: AppSpacing.xxs,
          bottom: _fabClearance,
        ),
        children: children,
      ),
    );
  }

  /// The list items for [load]: its content once there is some, a skeleton the
  /// first time, and the error with a retry when it failed. The items go
  /// straight into the ListView (not a Column) so long lists stay lazy.
  List<Widget> _itemsFor<T>(
    Reloadable<T> load,
    List<Widget> Function(T data) builder,
  ) {
    final data = load.data;
    if (data != null) return builder(data);
    if (load.hasFailed) {
      return [
        Padding(
          padding: const EdgeInsets.all(AppSemantic.screenPadding),
          child: ErrorView(
            message: friendlyError(load.error!),
            onRetry: _reloadAll,
          ),
        ),
      ];
    }
    return const [MatchListSkeleton()];
  }

  // ---- Opponents -----------------------------------------------------------

  Widget _buildOpponentsTab(TeamModel team) {
    return _tab(
      controller: _opponentsScroll,
      children: [
        OpponentFilters(
          city: _filterCity ?? _defaultCity,
          date: _filterDate,
          time: _filterTime,
          matchType: _filterMatchType,
          powerRange: _filterPowerRange,
          isFiltered: _filtersActive,
          onCityChanged: _setFilterCity,
          onDateChanged: _setFilterDate,
          onTimeChanged: _setFilterTime,
          onMatchTypeChanged: _setFilterMatchType,
          onPowerRangeChanged: _setFilterPowerRange,
          onReset: _resetFilters,
        ),
        ..._itemsFor<List<MatchRequestModel>>(_opponents, (all) {
          final range = _filterPowerRange;
          final visible = range <= 0
              ? all
              : all
                  .where((r) =>
                      ((r.teamRating ?? 1500) - team.rating).abs() <= range)
                  .toList();
          if (visible.isEmpty) {
            return [_opponentsEmpty(hiddenByRange: all.isNotEmpty)];
          }
          return [
            _ListCaption(
              '${visible.length} open '
              '${visible.length == 1 ? 'request' : 'requests'}',
            ),
            for (final (i, o) in visible.indexed)
              FadeSlideIn.listItem(
                key: ValueKey('opponent-${o.id}'),
                index: i,
                id: 'opponent-${o.id}',
                child: OpponentCard(
                  opponent: o,
                  myRating: team.rating,
                  onPropose: () => _propose(o),
                ),
              ),
            const _VenueDisclaimer(),
          ];
        }),
      ],
    );
  }

  Widget _opponentsEmpty({required bool hiddenByRange}) {
    final underStaffed = (_memberCount ?? 5) < 5;
    final String title;
    final String hint;
    if (hiddenByRange) {
      title = 'No teams in that power range';
      hint = 'Widen the range, or reset the filters to see every open '
          'request.';
    } else if (underStaffed) {
      title = 'No teams are searching right now';
      hint = 'Tap Create Match and let them come to you. You only need 5 '
          'players at match time, not right now.';
    } else if (_filtersActive) {
      title = 'No open requests match your filters';
      hint = 'Try a different date or time, or tap Create Match to post your '
          'own request.';
    } else {
      title = 'No open requests right now';
      hint = 'Tap Create Match to post your own request, and teams in your '
          'city can propose a match.';
    }
    return EmptyView(
      icon: Icons.person_search_outlined,
      title: title,
      hint: hint,
      // Creating a request is the floating button's job, always in reach;
      // the only action worth offering here is undoing the filters.
      action: _filtersActive
          ? AppButton(
              label: 'Reset filters',
              variant: AppButtonVariant.secondary,
              fullWidth: false,
              onPressed: _resetFilters,
            )
          : null,
    );
  }

  // ---- Activity ------------------------------------------------------------

  Widget _buildActivityTab(
    TeamModel team, {
    required int incoming,
    required int toConfirm,
  }) {
    return _tab(
      controller: _activityScroll,
      children: [
        FilterPills(
          index: _activityTab,
          items: [
            FilterPillItem('Requests', badgeCount: incoming),
            const FilterPillItem('Sent'),
            FilterPillItem('To confirm', badgeCount: toConfirm),
          ],
          onChanged: (i) => setState(() => _activityTab = i),
        ),
        ...switch (_activityTab) {
          0 => _requestItems(),
          1 => _sentItems(team),
          _ => _pendingItems(team),
        },
      ],
    );
  }

  List<Widget> _requestItems() {
    return _itemsFor<List<MatchRequestModel>>(_requests, (all) {
      final open =
          all.where((r) => MatchStatus.fromString(r.status).isOpen).toList();
      if (open.isEmpty) {
        return const [
          EmptyView(
            icon: Icons.sports_soccer_outlined,
            title: 'No open requests',
            hint: 'Tap Create Match to post a request, and teams in your city '
                'can propose a match.',
          ),
        ];
      }
      final Map<String, List<MatchProposalModel>> proposals =
          _isCaptain ? (_incoming.data ?? const {}) : const {};
      final uid = _userId;
      return [
        for (final (i, r) in open.indexed)
          FadeSlideIn.listItem(
            key: ValueKey('request-${r.id}'),
            index: i,
            id: 'request-${r.id}',
            child: RequestCard(
              request: r,
              onCancel: r.captainId == uid ? () => _cancelRequest(r) : null,
              onInvite: () => _inviteRival(r),
              proposals: proposals[r.id] ?? const [],
              onAcceptProposal: (p) => _acceptProposal(p, r),
              onRejectProposal: _rejectProposal,
            ),
          ),
      ];
    });
  }

  List<Widget> _sentItems(TeamModel team) {
    return _itemsFor<List<MatchProposalModel>>(_sent, (sent) {
      if (sent.isEmpty) {
        return const [
          EmptyView(
            icon: Icons.outgoing_mail,
            title: 'No pending proposals',
            hint: "Proposals your team sends to other teams' requests show up "
                'here while they are pending.',
          ),
        ];
      }
      return [
        for (final (i, p) in sent.indexed)
          FadeSlideIn.listItem(
            key: ValueKey('sent-${p.id}'),
            index: i,
            id: 'sent-${p.id}',
            child: SentProposalCard(proposal: p, myRating: team.rating),
          ),
      ];
    });
  }

  List<Widget> _pendingItems(TeamModel team) {
    return _itemsFor<List<MatchModel>>(_matches, (all) {
      final pending = all.where((m) => m.status == 'pending').toList();
      if (pending.isEmpty) {
        return const [
          EmptyView(
            icon: Icons.pending_actions_outlined,
            title: 'Nothing to confirm',
            hint: 'Matches that both captains still have to confirm appear '
                'here.',
          ),
        ];
      }
      return [
        for (final (i, m) in pending.indexed)
          FadeSlideIn.listItem(
            key: ValueKey('pending-${m.id}'),
            index: i,
            id: 'pending-${m.id}',
            child: PendingMatchCard(
              match: m,
              iConfirmed: m.homeTeamId == team.id ? m.homeOk : m.awayOk,
              canAct: _isCaptain,
              onConfirm: () => _confirmFixture(m),
              onReject: () => _rejectMatch(m),
            ),
          ),
      ];
    });
  }

  // ---- Matches -------------------------------------------------------------

  Widget _buildMatchesTab(TeamModel team) {
    final upcoming = _matchesTab == 0;
    return _tab(
      controller: _matchesScroll,
      children: [
        FilterPills(
          index: _matchesTab,
          items: const [FilterPillItem('Upcoming'), FilterPillItem('History')],
          onChanged: (i) => setState(() => _matchesTab = i),
        ),
        ..._itemsFor<List<MatchModel>>(_matches, (all) {
          // Soonest first for what is coming, latest first for what is done.
          final shown = all
              .where((m) => m.status == (upcoming ? 'confirmed' : 'completed'))
              .toList()
            ..sort((a, b) => upcoming
                ? a.scheduledAt.compareTo(b.scheduledAt)
                : b.scheduledAt.compareTo(a.scheduledAt));
          if (shown.isEmpty) {
            return [
              EmptyView(
                icon:
                    upcoming ? Icons.event_available_outlined : Icons.history,
                title: upcoming ? 'No upcoming matches' : 'No past matches yet',
                hint: upcoming
                    ? 'Matches you have confirmed show up here.'
                    : 'Finished matches and their results are listed here.',
              ),
            ];
          }
          return [
            for (final (i, m) in shown.indexed)
              FadeSlideIn.listItem(
                key: ValueKey('match-${m.id}'),
                index: i,
                id: 'match-${m.id}',
                child: MatchCard(
                  match: m,
                  myTeamId: team.id,
                  pendingFee: upcoming ? _pendingFees[m.id] : null,
                  onPaid: upcoming ? _loadPendingFees : null,
                ),
              ),
          ];
        }),
      ],
    );
  }
}

/// A small line of text above a list ("3 open requests").
class _ListCaption extends StatelessWidget {
  final String text;
  const _ListCaption(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSemantic.screenPadding,
        AppSpacing.xs,
        AppSemantic.screenPadding,
        AppSpacing.xxs,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.muted(context),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// The reminder that venue names are typed by captains, under the list of
/// opponents (where those names are shown).
class _VenueDisclaimer extends StatelessWidget {
  const _VenueDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        kVenueDisclaimer,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              height: 1.35,
              color: AppColors.muted(context),
            ),
      ),
    );
  }
}

/// The one solid-lime action on the screen. It presses in like every other
/// button (scale, haptic) and floats on a soft shadow.
class _CreateMatchButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CreateMatchButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadow = isDark
        ? Colors.black.withValues(alpha: 0.45)
        : AppColors.ink.withValues(alpha: 0.16);
    final onAction = AppColors.onAction(context);
    return PressableScale(
      onTap: onPressed,
      semanticLabel: 'Create match',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.action,
            borderRadius: BorderRadius.circular(AppSemantic.buttonRadius),
            boxShadow: [
              BoxShadow(
                color: shadow,
                blurRadius: AppSpacing.md,
                offset: const Offset(0, AppSpacing.xxs),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: AppSemantic.buttonHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: onAction),
                  const SizedBox(width: AppSemantic.iconGap),
                  // The button floats over the list, so it must never outgrow
                  // the screen: under the largest text sizes the label shrinks
                  // to fit instead of overflowing.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Create Match',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: AppTypeScale.button,
                          fontWeight: FontWeight.w700,
                          letterSpacing: AppTypeScale.trackButton,
                          color: onAction,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
