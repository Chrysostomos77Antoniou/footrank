import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/utils/maps_launcher.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_player_model.dart';
import 'package:footrank/models/match_status.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:url_launcher/url_launcher.dart';

class MatchDetailPage extends StatefulWidget {
  final String matchId;
  const MatchDetailPage({super.key, required this.matchId});

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  final _matchRepo = MatchRepository();
  final _teamRepo = TeamRepository();

  bool _loading = true;
  Object? _error;

  MatchModel? _match;
  bool _isCaptain = false;
  String? _myTeamId;
  String? _opponentTeamId;
  TeamModel? _homeTeam;
  TeamModel? _awayTeam;
  List<TeamMemberModel> _homeMembers = [];
  List<TeamMemberModel> _awayMembers = [];
  List<Map<String, dynamic>> _contacts = [];
  Map<String, MatchPlayerModel> _attendance = {};
  Map<String, String> _myBehavior = {}; // targetUserId -> 'good'|'bad'

  // Information / Contact / Attendance.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final match = await _matchRepo.fetchMatchById(widget.matchId);
      final uid = SupabaseService.client.auth.currentUser?.id;
      final home = await _teamRepo.fetchById(match.homeTeamId);
      final away = await _teamRepo.fetchById(match.awayTeamId);
      // Fetched once here (not per-rebuild) so marking attendance doesn't
      // re-trigger a network fetch that reflows the page and jumps the
      // scroll position back to the top.
      final homeMembers = await _teamRepo.fetchMembers(home.id);
      final awayMembers = await _teamRepo.fetchMembers(away.id);

      bool isCaptain = false;
      String? myTeamId;
      String? opponentTeamId;
      if (uid == home.captainId) {
        isCaptain = true;
        myTeamId = home.id;
        opponentTeamId = away.id;
      } else if (uid == away.captainId) {
        isCaptain = true;
        myTeamId = away.id;
        opponentTeamId = home.id;
      } else if (homeMembers.any((m) => m.userId == uid)) {
        myTeamId = home.id;
        opponentTeamId = away.id;
      } else if (awayMembers.any((m) => m.userId == uid)) {
        myTeamId = away.id;
        opponentTeamId = home.id;
      }

      final attendance = await _matchRepo.fetchAttendance(match.id);
      final behavior = await _matchRepo.fetchMyBehavior(match.id);
      // Participant-only captain contacts (RPC throws for non-participants).
      List<Map<String, dynamic>> contacts = [];
      try {
        contacts = await _matchRepo.matchCaptainContacts(match.id);
      } catch (_) {
        contacts = [];
      }

      if (!mounted) return;
      setState(() {
        _match = match;
        _isCaptain = isCaptain;
        _myTeamId = myTeamId;
        _opponentTeamId = opponentTeamId;
        _homeTeam = home;
        _awayTeam = away;
        _homeMembers = homeMembers;
        _awayMembers = awayMembers;
        _contacts = contacts;
        _attendance = attendance;
        _myBehavior = behavior;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _mark(TeamMemberModel player, bool attended) async {
    final match = _match!;
    // No upper bound: a squad can field more than 5 across a match (rolling
    // subs), so any number can be marked attended. submitScore enforces the
    // floor of 5 -- a side must show at least a full team actually played.
    try {
      await _matchRepo.markAttendance(
        matchId: match.id,
        userId: player.userId,
        teamId: player.teamId,
        attended: attended,
      );
      setState(() {
        _attendance[player.userId] = MatchPlayerModel(
          matchId: match.id,
          userId: player.userId,
          teamId: player.teamId,
          attended: attended,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _rate(
    TeamMemberModel player,
    String rating, {
    String? reason,
  }) async {
    final match = _match!;
    if (!_matchStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can rate players 90 minutes after kick-off (from ${_kickoffLabel()}).',
          ),
        ),
      );
      return;
    }
    try {
      await _matchRepo.submitBehavior(
        matchId: match.id,
        targetUserId: player.userId,
        rating: rating,
        reason: reason,
      );
      setState(() => _myBehavior[player.userId] = rating);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  /// One rating applies to the whole opposing squad at once -- the captain
  /// judges the team's conduct as a unit rather than assessing each player
  /// individually, but under the hood it's still recorded per player so
  /// each opponent's own reliability/behavior stats stay accurate.
  Future<void> _rateTeamGood(List<TeamMemberModel> members) async {
    for (final m in members) {
      await _rate(m, 'good');
    }
  }

  Future<void> _rateTeamBad(
    List<TeamMemberModel> members,
    String teamName,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _ReasonDialog(playerName: teamName),
    );
    if (reason == null) return; // cancelled
    for (final m in members) {
      await _rate(m, 'bad', reason: reason);
    }
  }

  Future<void> _submitScore() async {
    final match = _match!;
    if (!_matchStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can submit the score 90 minutes after kick-off (from ${_kickoffLabel()}).',
          ),
        ),
      );
      return;
    }
    // Squads of 5 or fewer are auto-marked attended on confirmation, so this
    // only ever blocks a captain with a bench (6+ squad) who hasn't picked
    // at least 5 yet -- the server enforces the same floor either way. No
    // upper bound: more than 5 is fine (rolling substitutes).
    final attendedCount = _attendance.values
        .where((p) => p.teamId == _myTeamId && p.attended == true)
        .length;
    if (attendedCount < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mark at least 5 attended players for your team before submitting a score.',
          ),
        ),
      );
      return;
    }
    final result = await showDialog<({int home, int away})>(
      context: context,
      builder: (ctx) => _ScoreDialog(
        homeName: match.homeTeamName ?? 'Home',
        awayName: match.awayTeamName ?? 'Away',
        initialHome: match.homeScore,
        initialAway: match.awayScore,
      ),
    );
    if (result == null) return;
    try {
      final status = await _matchRepo.submitScore(
        matchId: match.id,
        homeScore: result.home,
        awayScore: result.away,
      );
      if (mounted) {
        final msg = switch (status) {
          'completed' => 'Both captains agree on the winner — match completed!',
          'disputed' =>
            'Your report disagrees with the opponent on the winner. '
                'Please check and re-submit.',
          'resolved' =>
            'Still disagreeing — resolved automatically in favour of the more '
                'trusted captain. Match completed.',
          _ => 'Score submitted. Waiting for the opponent\'s report.',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _reschedule() async {
    final match = _match!;
    final current = match.scheduledAt.toLocal();
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null) return;
    final newDt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    try {
      await _matchRepo.rescheduleMatch(match.id, newDt);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Match rescheduled')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  /// Confirmed matches can be cancelled any time, but a captain who cancels
  /// from the 2-hour mark before kick-off onward (including after kick-off,
  /// if it was never scored) costs their team 200 Pitch Power. Matches that
  /// aren't mutually confirmed yet ('pending') stay free to back out of.
  Future<void> _cancelMatch() async {
    final match = _match!;
    if (match.status != 'confirmed') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel this match?'),
          content: const Text(
            'This removes the match for both teams. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel match'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await _matchRepo.cancelMatch(match.id);
        if (!mounted) return;
        triggerAppRefresh();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Match cancelled')));
        Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e.toString().replaceFirst('Exception: ', ''))),
          );
        }
      }
      return;
    }

    final cutoff = match.scheduledAt.subtract(const Duration(hours: 2));
    final tooLate = !DateTime.now().toUtc().isBefore(cutoff);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this match?'),
        content: Text(tooLate
            ? 'Kick-off is less than 2 hours away. If you cancel now, your '
                'team will lose 200 Pitch Power. This cannot be undone.'
            : 'This removes the match for both teams and reopens the slot '
                'for the opponent to find a new match. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tooLate ? 'Cancel & lose 200 PWR' : 'Cancel match'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final penalized = await _matchRepo.cancelConfirmedMatch(match.id);
      if (!mounted) return;
      triggerAppRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(penalized
                ? 'Match cancelled — your team lost 200 Pitch Power.'
                : 'Match cancelled.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  /// Score & behavior unlock 90 minutes after the scheduled kick-off.
  DateTime get _submissionOpensAt =>
      _match!.scheduledAt.add(const Duration(minutes: 90));

  bool get _matchStarted =>
      _match != null && DateTime.now().toUtc().isAfter(_submissionOpensAt);

  String _kickoffLabel() {
    final d = _submissionOpensAt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        'at ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String? _reportText(int? h, int? a) =>
      (h == null || a == null) ? null : '$h - $a';

  Widget _buildContactCard() {
    if (_contacts.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (final c in _contacts) {
      final tid = c['team_id'] as String?;
      final name = (c['captain_name'] as String?) ?? 'Captain';
      final phone = c['captain_phone'] as String?;
      final teamName = tid == _match?.homeTeamId
          ? (_homeTeam?.name ?? 'Home')
          : (_awayTeam?.name ?? 'Away');
      rows.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: GradientAvatar(name: name, radius: 18),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '$teamName captain'
            '${phone != null && phone.isNotEmpty ? ' · $phone' : ''}',
          ),
          trailing: (phone != null && phone.isNotEmpty)
              ? IconButton(
                  icon: Icon(Icons.call, color: AppColors.iconAccent(context)),
                  onPressed: () => _call(phone),
                )
              : null,
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Captains', style: Theme.of(context).textTheme.titleMedium),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildScoreSection() {
    final match = _match!;
    final iAmHome = _myTeamId == match.homeTeamId;
    final myReport = iAmHome
        ? _reportText(match.homeReportH, match.homeReportA)
        : _reportText(match.awayReportH, match.awayReportA);
    final oppReport = iAmHome
        ? _reportText(match.awayReportH, match.awayReportA)
        : _reportText(match.homeReportH, match.homeReportA);

    final List<Widget> children = [
      Text('Final Score', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
    ];

    if (match.status == 'completed') {
      children.add(
        Text(
          '${match.homeTeamName ?? 'Home'} ${match.homeScore} - '
          '${match.awayScore} ${match.awayTeamName ?? 'Away'}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      );
      children.add(const SizedBox(height: 4));
      children.add(
        Text(
          'Result confirmed by both captains.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    } else if (!_matchStarted) {
      children.add(
        Row(
          children: [
            const Icon(Icons.lock_clock, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The score can be submitted 90 minutes after kick-off '
                '(from ${_kickoffLabel()}).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    } else {
      // Submission window open, not yet completed.
      children.add(Text('Your team\'s report: ${myReport ?? 'not submitted'}'));
      children.add(const SizedBox(height: 4));
      children.add(
        Text(
          'Opponent\'s report: ${oppReport ?? 'not submitted'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
      children.add(const SizedBox(height: 8));

      if (match.scoreDisputed) {
        children.add(
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The two captains reported different winners. Please check '
                    'with each other and re-submit. If you disagree again, the '
                    'result is decided by the more trusted captain (fewer past '
                    'disputes). Repeated disputes can get a captain flagged and '
                    'cost the team 500 rating.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
        children.add(const SizedBox(height: 10));
      } else if (myReport != null && oppReport == null) {
        children.add(
          Text(
            'Waiting for the opponent to submit their score. If they '
            "haven't within 24 hours, your reported score becomes official.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
        children.add(const SizedBox(height: 10));
      }

      children.add(
        FilledButton.icon(
          onPressed: _submitScore,
          icon: const Icon(Icons.scoreboard),
          label: Text(myReport == null ? 'Submit Score' : 'Re-submit Score'),
        ),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canReschedule =
        _isCaptain && _match != null && _match!.status != 'completed';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Match'),
        actions: [
          if (canReschedule)
            IconButton(
              tooltip: 'Reschedule',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: _reschedule,
            ),
          if (canReschedule)
            IconButton(
              tooltip: 'Cancel match',
              icon: const Icon(Icons.cancel_outlined),
              onPressed: _cancelMatch,
            ),
        ],
      ),
      body: AmbientBackground(child: SafeArea(child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorView(
        message: friendlyError(_error!),
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }

    final match = _match!;
    final status = MatchStatus.fromString(match.status);
    final hasScore = match.homeScore != null && match.awayScore != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FadeSlideIn(
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _TeamHeader(
                    name: match.homeTeamName ?? 'Home',
                    onTap: _homeTeam == null
                        ? null
                        : () => showTeamSheet(context, _homeTeam!),
                  ),
                ),
                Text(
                  hasScore ? '${match.homeScore} - ${match.awayScore}' : 'VS',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: _TeamHeader(
                    name: match.awayTeamName ?? 'Away',
                    onTap: _awayTeam == null
                        ? null
                        : () => showTeamSheet(context, _awayTeam!),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isCaptain && status != MatchStatus.completed) ...[
          const SizedBox(height: 8),
          FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: _buildScoreSection()),
        ],
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          child: GlassTabs(
            index: _tab,
            tabs: const ['Information', 'Contact', 'Attendance', 'Behave'],
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: const Duration(milliseconds: 160),
          child: IndexedStack(
            index: _tab,
            alignment: Alignment.topCenter,
            children: [
              _buildInfoTab(match, status),
              _buildContactTab(),
              _buildAttendanceTab(match),
              _buildRateTab(match),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRateTab(MatchModel match) {
    if (!_isCaptain || _opponentTeamId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: EmptyView(
          icon: Icons.thumbs_up_down_outlined,
          title: 'Only captains can rate the opposition',
        ),
      );
    }
    if (!_matchStarted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Text(
          'You can rate the opposition\'s behavior 90 minutes after '
          'kick-off (from ${_kickoffLabel()}).',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final opponentMembers =
        _opponentTeamId == match.homeTeamId ? _homeMembers : _awayMembers;
    final title = _opponentTeamId == match.homeTeamId
        ? (match.homeTeamName ?? 'Home')
        : (match.awayTeamName ?? 'Away');
    if (opponentMembers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: EmptyView(
          icon: Icons.groups_outlined,
          title: 'No opposition roster to rate yet',
        ),
      );
    }
    // "Rated" only once every opponent has the SAME rating recorded, since
    // team rating is always applied to the whole squad in one action.
    final ratedValues = opponentMembers.map((m) => _myBehavior[m.userId]).toSet();
    final currentRating =
        ratedValues.length == 1 ? ratedValues.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rate how $title behaved as a team -- this applies to every '
          'player on their side, not each one separately.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              GradientAvatar(name: title, radius: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              _BehaviorControl(
                rating: currentRating,
                onGood: () => _rateTeamGood(opponentMembers),
                onBad: () => _rateTeamBad(opponentMembers, title),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTab(MatchModel match, MatchStatus status) {
    final d = match.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}'
        ' · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Column(
      children: [
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Time'),
                trailing: Text(when),
              ),
              ListTile(
                leading: const Icon(Icons.place),
                title: const Text('City'),
                trailing: Text(match.city),
              ),
              ListTile(
                leading: const Icon(Icons.flag),
                title: const Text('Status'),
                trailing: _StatusChip(status: status),
              ),
              ListTile(
                leading: const Icon(Icons.groups),
                title: const Text('Type / Format'),
                trailing: Text('${match.matchType} · ${match.format}'),
              ),
            ],
          ),
        ),
        if (match.suggestedCourtId != null) ...[
          const SizedBox(height: 8),
          _SuggestedCourtCard(match: match),
        ],
      ],
    );
  }

  Widget _buildContactTab() {
    if (_contacts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: EmptyView(
          icon: Icons.contact_phone_outlined,
          title: 'No contacts to show yet',
        ),
      );
    }
    return _buildContactCard();
  }

  Widget _buildAttendanceTab(MatchModel match) {
    if (_myTeamId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: EmptyView(
          icon: Icons.groups_outlined,
          title: 'You are not part of either squad',
        ),
      );
    }
    final myTeamName = _myTeamId == match.homeTeamId
        ? (match.homeTeamName ?? 'Home')
        : (match.awayTeamName ?? 'Away');
    final myMembers = _myTeamId == match.homeTeamId ? _homeMembers : _awayMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isCaptain)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Mark which of your players actually played (at least 5). '
              'You can change a mark any time before the score is submitted.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 4),
        _TeamRoster(
          title: myTeamName,
          members: myMembers,
          attendance: _attendance,
          canMark: _isCaptain,
          onMark: _mark,
        ),
      ],
    );
  }
}

class _TeamHeader extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;
  const _TeamHeader({required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand(context), width: 2.5),
            ),
            child: GradientAvatar(name: name, radius: 28),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (onTap != null)
            Text(
              'Tap to view',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.brand(context),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final MatchStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.isCompleted
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// A single team's squad list. Purely presentational -- takes the already
/// fetched [members] instead of re-fetching on every rebuild, which used to
/// cause a loading-spinner flicker (and the resulting scroll jump) every
/// time a captain marked one player's attendance.
class _TeamRoster extends StatelessWidget {
  final String title;
  final List<TeamMemberModel> members;
  final Map<String, MatchPlayerModel> attendance;
  final bool canMark;
  final void Function(TeamMemberModel player, bool attended) onMark;

  const _TeamRoster({
    required this.title,
    required this.members,
    required this.attendance,
    required this.canMark,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title — Players',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          const EmptyView(
            icon: Icons.person_off_outlined,
            title: 'No players listed',
          )
        else
          Column(
            children: members.asMap().entries.map((e) {
              final m = e.value;
              final att = attendance[m.userId]?.attended;
              final Widget trailing = canMark
                  ? _AttendanceToggle(
                      attended: att,
                      onPresent: () => onMark(m, true),
                      onAbsent: () => onMark(m, false),
                    )
                  : _AttendanceBadge(attended: att);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FadeSlideIn(
                  delay: Duration(milliseconds: 40 * e.key),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () => showPlayerSheetById(context, m.userId),
                    child: Row(
                      children: [
                        GradientAvatar(name: m.name, radius: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              if (m.position != null)
                                Text(m.position!,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        LevelBadge(value: m.elo, size: 36),
                        trailing,
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _AttendanceToggle extends StatelessWidget {
  final bool? attended;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;

  const _AttendanceToggle({
    required this.attended,
    required this.onPresent,
    required this.onAbsent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.check_circle,
            color: attended == true
                ? AppColors.success
                : AppColors.muted(context),
          ),
          tooltip: 'Attended',
          onPressed: onPresent,
        ),
        IconButton(
          icon: Icon(
            Icons.cancel,
            color: attended == false
                ? AppColors.danger
                : AppColors.muted(context),
          ),
          tooltip: 'Did not attend',
          onPressed: onAbsent,
        ),
      ],
    );
  }
}

class _AttendanceBadge extends StatelessWidget {
  final bool? attended;
  const _AttendanceBadge({required this.attended});

  @override
  Widget build(BuildContext context) {
    if (attended == null) return const SizedBox.shrink();
    return Icon(
      attended! ? Icons.check_circle : Icons.cancel,
      color: attended! ? AppColors.success : AppColors.danger,
    );
  }
}

class _BehaviorControl extends StatelessWidget {
  final String? rating; // null = not yet rated
  final VoidCallback onGood;
  final VoidCallback onBad;

  const _BehaviorControl({
    required this.rating,
    required this.onGood,
    required this.onBad,
  });

  @override
  Widget build(BuildContext context) {
    if (rating != null) {
      // Already rated — show the chosen verdict, locked.
      final good = rating == 'good';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          good ? Icons.thumb_up : Icons.thumb_down,
          color: good ? AppColors.success : AppColors.danger,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.thumb_up_outlined),
          tooltip: 'Good behavior',
          onPressed: onGood,
        ),
        IconButton(
          icon: const Icon(Icons.thumb_down_outlined),
          tooltip: 'Bad behavior',
          onPressed: onBad,
        ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  final String playerName;
  const _ReasonDialog({required this.playerName});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report ${widget.playerName}'),
      content: TextField(
        controller: _ctrl,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Reason',
          hintText: 'What went wrong?',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _ctrl.text.trim();
            if (reason.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a reason')),
              );
              return;
            }
            Navigator.pop(context, reason);
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _ScoreDialog extends StatefulWidget {
  final String homeName;
  final String awayName;
  final int? initialHome;
  final int? initialAway;

  const _ScoreDialog({
    required this.homeName,
    required this.awayName,
    this.initialHome,
    this.initialAway,
  });

  @override
  State<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends State<_ScoreDialog> {
  late final _homeCtrl = TextEditingController(
    text: widget.initialHome?.toString() ?? '',
  );
  late final _awayCtrl = TextEditingController(
    text: widget.initialAway?.toString() ?? '',
  );

  @override
  void dispose() {
    _homeCtrl.dispose();
    _awayCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final h = int.tryParse(_homeCtrl.text.trim());
    final a = int.tryParse(_awayCtrl.text.trim());
    if (h == null || a == null || h < 0 || a < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter valid scores')));
      return;
    }
    Navigator.pop(context, (home: h, away: a));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Final Score'),
      content: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.homeName, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextField(
                  controller: _homeCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('-', style: TextStyle(fontSize: 24)),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.awayName, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextField(
                  controller: _awayCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Submit')),
      ],
    );
  }
}

/// Both captains rank their 3 courts when creating their match request; once
/// matched, the backend resolves a suggested court automatically (see
/// accept_match_request()). Read-only display here — deliberately shows
/// name/address/photo only, never a phone number; the owner sees that
/// separately when making the actual booking call.
class _SuggestedCourtCard extends StatelessWidget {
  final MatchModel match;
  const _SuggestedCourtCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final name = match.suggestedCourtName ?? 'Court';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested Court',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (match.suggestedCourtImageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                match.suggestedCourtImageUrl!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (match.suggestedCourtAddress != null)
            Text(
              match.suggestedCourtAddress!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => openInMaps(
                name: name,
                address: match.suggestedCourtAddress,
                city: match.city,
              ),
              icon: const Icon(Icons.directions),
              label: const Text('Get Directions'),
            ),
          ),
        ],
      ),
    );
  }
}
