import 'package:footrank/match/data/court_repository.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_player_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/services/elo_engine.dart';
import 'package:footrank/services/supabase_service.dart';

class MatchRepository {
  static const _requests = 'match_requests';
  static const _requestProposals = 'match_request_proposals';
  static const _matches = 'matches';
  static const _matchPlayers = 'match_players';
  static const _behavior = 'behavior_reports';
  final _courtRepo = CourtRepository();

  /// Combined ranked-choice score between two teams' 3 court picks (mirrors
  /// the DB's accept_match_request resolution): 1st choice = 3pts, 2nd =
  /// 2pts, 3rd = 1pt: highest SUM for a court on both lists wins. A court on
  /// only one list, or no overlap at all, scores 0.
  static int _courtCompatibility(List<String> mine, List<String> theirs) {
    var best = 0;
    for (var i = 0; i < mine.length; i++) {
      final j = theirs.indexOf(mine[i]);
      if (j == -1) continue;
      final score = (3 - i) + (3 - j);
      if (score > best) best = score;
    }
    return best;
  }

  /// Default discovery windows, shared by findOpponents and findAllOpponents so
  /// both code paths use identical matching rules.
  // Loosened for a thin team pool: a wider time window and ELO band surface
  // more potential opponents (tighten again as the network grows).
  static const int defaultWithinMinutes = 60;
  static const int defaultEloThreshold = 250;

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// Creates a match request for the captain's team, with a single chosen
  /// court in [city]. That court is exactly the one shown to browsing
  /// captains and the one used as the match's court once a proposal is
  /// accepted -- no ranked-choice comparison, since there's nothing to
  /// compare a single pick against.
  Future<MatchRequestModel> createMatchRequest({
    required String teamId,
    required String city,
    required DateTime scheduledAt,
    required String matchType,
    required String courtId,
    String format = '5v5',
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');

    final inserted = await SupabaseService.client
        .from(_requests)
        .insert({
          'team_id': teamId,
          'captain_id': uid,
          'city': city,
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
          'match_type': matchType,
          'format': format,
        })
        .select('*, teams(name)')
        .single();

    final request = MatchRequestModel.fromJson(inserted);
    await _courtRepo.insertRequestCourtPicks(request.id, [courtId]);
    return request;
  }

  /// Checks whether [teamId] already has an open request or confirmed match
  /// within an hour of [scheduledAt] -- mirrors the server-side guard in
  /// enforce_no_overlapping_team_commitment(), so the UI can reject with a
  /// friendly, specific message before the request ever hits the API.
  /// Returns the conflicting time (local) if one exists, otherwise null.
  Future<DateTime?> findSchedulingConflict({
    required String teamId,
    required DateTime scheduledAt,
  }) async {
    final anchor = scheduledAt.toUtc();
    final from = anchor.subtract(const Duration(hours: 1));
    final to = anchor.add(const Duration(hours: 1));

    final requests = await SupabaseService.client
        .from(_requests)
        .select('scheduled_at')
        .eq('team_id', teamId)
        .eq('status', 'searching')
        .gte('scheduled_at', from.toIso8601String())
        .lte('scheduled_at', to.toIso8601String())
        .limit(1);
    if ((requests as List).isNotEmpty) {
      return DateTime.parse(requests.first['scheduled_at'] as String)
          .toLocal();
    }

    final matches = await SupabaseService.client
        .from(_matches)
        .select('scheduled_at')
        .or('home_team_id.eq.$teamId,away_team_id.eq.$teamId')
        .gte('scheduled_at', from.toIso8601String())
        .lte('scheduled_at', to.toIso8601String())
        .limit(1);
    if ((matches as List).isNotEmpty) {
      return DateTime.parse(matches.first['scheduled_at'] as String)
          .toLocal();
    }

    return null;
  }

  /// Match requests created by the current captain's team.
  Future<List<MatchRequestModel>> fetchMyTeamRequests(String teamId) async {
    final data = await SupabaseService.client
        .from(_requests)
        .select('*, teams(name, rating, logo_url)')
        .eq('team_id', teamId)
        .order('scheduled_at');

    return (data as List)
        .map((e) => MatchRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The team's open ('searching') requests — used as references for discovery.
  Future<List<MatchRequestModel>> fetchSearchingRequests(String teamId) async {
    final data = await SupabaseService.client
        .from(_requests)
        .select('*, teams(name, rating, logo_url)')
        .eq('team_id', teamId)
        .eq('status', 'searching')
        .order('scheduled_at');

    return (data as List)
        .map((e) => MatchRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Finds opponent requests matching a reference request:
  ///  - same city (case-insensitive)
  ///  - scheduled time within [withinMinutes] of the reference
  ///  - opponent team rating within [eloThreshold] of [myTeamRating]
  ///  - still 'searching' and not the requesting team
  ///
  /// Results are RANKED (not just filtered), in priority order: how well the
  /// opponent's 3 ranked court picks overlap with [myCourtIds] first, then
  /// closeness in kick-off time, then closeness in rating.
  Future<List<MatchRequestModel>> findOpponents({
    required String myTeamId,
    required int myTeamRating,
    required String city,
    required DateTime scheduledAt,
    required List<String> myCourtIds,
    int withinMinutes = defaultWithinMinutes,
    int eloThreshold = defaultEloThreshold,
  }) async {
    // scheduled_at is stored in UTC (see createMatchRequest / rescheduleMatch),
    // so the window bounds MUST be UTC too. Building them from a local DateTime
    // shifted the gte/lte range by the user's UTC offset and silently dropped
    // otherwise-valid opponents for anyone not on UTC.
    final anchor = scheduledAt.toUtc();
    final from =
        anchor.subtract(Duration(minutes: withinMinutes)).toIso8601String();
    final to = anchor.add(Duration(minutes: withinMinutes)).toIso8601String();

    final data = await SupabaseService.client
        .from(_requests)
        .select('*, teams(name, rating, logo_url)')
        .eq('status', 'searching')
        .neq('team_id', myTeamId)
        .ilike('city', city.trim())
        .gte('scheduled_at', from)
        .lte('scheduled_at', to)
        .order('scheduled_at');

    final candidates = (data as List)
        .map((e) => MatchRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // ELO proximity is filtered client-side (needs abs of joined rating).
    final withinElo = candidates.where((r) {
      final rating = r.teamRating;
      if (rating == null) return false;
      return (rating - myTeamRating).abs() <= eloThreshold;
    }).toList();

    if (withinElo.isEmpty) return withinElo;

    final picksById = await _courtRepo
        .fetchPicksForRequests(withinElo.map((r) => r.id).toList());

    final scored = withinElo
        .map((r) => r.copyWith(
            courtCompatibilityScore:
                _courtCompatibility(myCourtIds, picksById[r.id] ?? const [])))
        .toList();

    scored.sort((a, b) {
      final byCourt = (b.courtCompatibilityScore ?? 0)
          .compareTo(a.courtCompatibilityScore ?? 0);
      if (byCourt != 0) return byCourt;
      final aTimeDiff =
          a.scheduledAt.difference(scheduledAt).inMinutes.abs();
      final bTimeDiff =
          b.scheduledAt.difference(scheduledAt).inMinutes.abs();
      final byTime = aTimeDiff.compareTo(bTimeDiff);
      if (byTime != 0) return byTime;
      final aEloDiff = ((a.teamRating ?? myTeamRating) - myTeamRating).abs();
      final bEloDiff = ((b.teamRating ?? myTeamRating) - myTeamRating).abs();
      return aEloDiff.compareTo(bEloDiff);
    });

    return scored;
  }

  /// Captain cancels/deletes one of their own open match requests.
  /// Only allowed while still 'searching' (no opponent matched yet).
  Future<void> deleteRequest(String requestId) async {
    await SupabaseService.client
        .from(_requests)
        .delete()
        .eq('id', requestId)
        .eq('status', 'searching');
  }

  /// Browse every open ('searching') request from OTHER teams in [city] --
  /// no requirement that the viewing team has an open request of its own.
  /// [courtId] narrows to requests that picked that court; [date] narrows to
  /// requests scheduled on that calendar day; [timeOfDay] (minutes since
  /// midnight, local) narrows to requests within an hour of that time on any
  /// day; [matchType] narrows to 'casual' or 'ranked'. All are optional
  /// except [city]. Each result carries its court pick (see
  /// [MatchRequestModel.courtPicks]) so captains can see where a match would
  /// be played before proposing.
  Future<List<MatchRequestModel>> fetchCityRequests({
    required String city,
    required String excludeTeamId,
    String? courtId,
    DateTime? date,
    int? timeOfDayMinutes,
    String? matchType,
  }) async {
    var query = SupabaseService.client
        .from(_requests)
        .select('*, teams(name, rating, logo_url)')
        .eq('status', 'searching')
        .neq('team_id', excludeTeamId)
        .ilike('city', city.trim())
        // A match can't be played retroactively, so skip requests already in
        // the past (the stale records that pile up without a cleanup job).
        .gte(
          'scheduled_at',
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        );

    if (date != null) {
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      query = query
          .gte('scheduled_at', dayStart.toUtc().toIso8601String())
          .lt('scheduled_at', dayEnd.toUtc().toIso8601String());
    }
    if (matchType != null) {
      query = query.eq('match_type', matchType);
    }

    final data = await query.order('scheduled_at');
    var requests = (data as List)
        .map((e) => MatchRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();

    if (timeOfDayMinutes != null) {
      requests = requests.where((r) {
        final local = r.scheduledAt.toLocal();
        final minutes = local.hour * 60 + local.minute;
        return (minutes - timeOfDayMinutes).abs() <= 60;
      }).toList();
    }

    // Hide any request the viewing team already has a pending proposal on --
    // once a teammate proposes, the whole team stops seeing it in the browse
    // list. It reappears (and can be proposed to again) once that proposal
    // is no longer pending (rejected, or cancelled by the same-date cascade).
    if (requests.isNotEmpty) {
      final pending = await SupabaseService.client
          .from(_requestProposals)
          .select('request_id')
          .eq('proposing_team_id', excludeTeamId)
          .eq('status', 'pending');
      final pendingRequestIds = (pending as List)
          .map((e) => (e as Map<String, dynamic>)['request_id'] as String)
          .toSet();
      requests =
          requests.where((r) => !pendingRequestIds.contains(r.id)).toList();
    }
    if (requests.isEmpty) return requests;

    final picksById = await _courtRepo
        .fetchPicksWithCourtsForRequests(requests.map((r) => r.id).toList());

    final withPicks =
        requests.map((r) => r.copyWith(courtPicks: picksById[r.id] ?? const []))
            .toList();

    if (courtId == null) return withPicks;
    return withPicks
        .where((r) => r.courtPicks!.any((c) => c.id == courtId))
        .toList();
  }

  // ---- Propose / Accept / Reject (browse-and-propose flow) ----

  /// Any member of [teamId] can propose against an open [requestId] --
  /// proposing isn't captain-restricted, only accepting/rejecting is. Does
  /// NOT lock the request -- it stays 'searching' (and other teams can
  /// still propose) until the request's own captain accepts one proposal.
  Future<String> proposeMatch({
    required String requestId,
    required String teamId,
  }) async {
    final result = await SupabaseService.client.rpc(
      'propose_match',
      params: {'p_request_id': requestId, 'p_team_id': teamId},
    );
    return result as String;
  }

  /// Captain-only (the request's own captain): accepts one pending proposal.
  /// Creates the confirmed match immediately and auto-cancels every other
  /// pending proposal on the same request. Returns the new match id.
  Future<String> acceptProposal(String proposalId) async {
    final result = await SupabaseService.client.rpc(
      'accept_match_proposal',
      params: {'p_proposal_id': proposalId},
    );
    return result as String;
  }

  /// Captain-only (the request's own captain): declines one pending
  /// proposal. The request stays open for other proposals.
  Future<void> rejectProposal(String proposalId) => SupabaseService.client
      .rpc('reject_match_proposal', params: {'p_proposal_id': proposalId});

  /// Pending proposals against every open request [teamId] has posted --
  /// shown to the captain so they can accept/reject each one.
  Future<Map<String, List<MatchProposalModel>>> fetchProposalsForTeamRequests(
    String teamId,
  ) async {
    final myRequests = await fetchSearchingRequests(teamId);
    if (myRequests.isEmpty) return {};

    final data = await SupabaseService.client
        .from(_requestProposals)
        .select('*, teams(name, rating, logo_url)')
        .inFilter('request_id', myRequests.map((r) => r.id).toList())
        .eq('status', 'pending')
        .order('created_at');

    final map = <String, List<MatchProposalModel>>{};
    for (final e in data as List) {
      final row = e as Map<String, dynamic>;
      final proposal = MatchProposalModel.fromJson(row);
      (map[proposal.requestId] ??= []).add(proposal);
    }
    return map;
  }

  /// Every OPEN (pending) proposal [teamId] has sent to other teams'
  /// requests -- visible to every team member, not just the captain, so
  /// anyone can see what the team has already proposed (these are exactly
  /// the requests hidden from [fetchCityRequests] while pending).
  Future<List<MatchProposalModel>> fetchSentProposals(String teamId) async {
    final data = await SupabaseService.client
        .from(_requestProposals)
        .select(
            '*, match_requests(city, scheduled_at, match_type, format, teams(name, rating, logo_url))')
        .eq('proposing_team_id', teamId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => MatchProposalModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Accept / Reject (Task 5.3) ----

  /// Opponent captain accepts [requestId]; creates a match and confirms the
  /// request atomically (via DB function). [myRequestId] is the accepting
  /// captain's own reference request, if they have one — its ranked court
  /// picks are compared against the accepted request's to resolve a
  /// suggested court immediately. When null (accepting directly from the
  /// city browse list, with no request of your own), the suggested court
  /// falls back to the requesting team's #1 choice. Returns the new match id.
  Future<String> acceptMatchRequest({
    required String requestId,
    required String awayTeamId,
    String? myRequestId,
  }) async {
    final result = await SupabaseService.client.rpc(
      'accept_match_request',
      params: {
        'p_request_id': requestId,
        'p_away_team_id': awayTeamId,
        'p_my_request_id': myRequestId,
      },
    );
    return result as String;
  }

  /// Cancel/decline a pending or confirmed (not completed) match.
  Future<void> cancelMatch(String matchId) =>
      SupabaseService.client.rpc('cancel_match', params: {'p_match_id': matchId});

  /// Captain cancels an already-CONFIRMED (upcoming) match. Free more than 2
  /// hours before kick-off; from the 2-hour mark onward (including after
  /// kick-off, if it was never scored) the cancelling team loses 200 Pitch
  /// Power. The opponent's slot is reopened into the matchmaking pool either
  /// way. Returns true if the penalty was applied.
  Future<bool> cancelConfirmedMatch(String matchId) async {
    final result = await SupabaseService.client
        .rpc('cancel_confirmed_match', params: {'p_match_id': matchId});
    return (result as Map<String, dynamic>)['penalized'] as bool? ?? false;
  }

  /// Captains' contact details for a match — participants only.
  Future<List<Map<String, dynamic>>> matchCaptainContacts(String matchId) async {
    final data = await SupabaseService.client
        .rpc('match_captain_contacts', params: {'p_match_id': matchId});
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// The other captain confirms the fixture. Returns 'pending' or 'confirmed'.
  Future<String> confirmFixture(String matchId) async {
    final result = await SupabaseService.client
        .rpc('confirm_fixture', params: {'p_match_id': matchId});
    return result as String;
  }

  /// A single match with both team names.
  Future<MatchModel> fetchMatchById(String matchId) async {
    final data = await SupabaseService.client
        .from(_matches)
        .select(
            '*, home_team:home_team_id(name, logo_url, rating, wins, losses, draws), away_team:away_team_id(name, logo_url, rating, wins, losses, draws), suggested_court:suggested_court_id(name, address, image_url)')
        .eq('id', matchId)
        .single();
    return MatchModel.fromJson(data);
  }

  /// Confirmed/completed matches involving the given team.
  Future<List<MatchModel>> fetchTeamMatches(String teamId) async {
    final data = await SupabaseService.client
        .from(_matches)
        .select(
            '*, home_team:home_team_id(name, logo_url, rating, wins, losses, draws), away_team:away_team_id(name, logo_url, rating, wins, losses, draws), suggested_court:suggested_court_id(name, address, image_url)')
        .or('home_team_id.eq.$teamId,away_team_id.eq.$teamId')
        .order('scheduled_at', ascending: false);

    return (data as List)
        .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Attendance (Task 6.2) ----

  /// Attendance records for a match, keyed by user_id.
  Future<Map<String, MatchPlayerModel>> fetchAttendance(String matchId) async {
    final data = await SupabaseService.client
        .from(_matchPlayers)
        .select()
        .eq('match_id', matchId);

    final map = <String, MatchPlayerModel>{};
    for (final e in data as List) {
      final mp = MatchPlayerModel.fromJson(e as Map<String, dynamic>);
      map[mp.userId] = mp;
    }
    return map;
  }

  /// Captain marks one of their own players attended / not attended (upsert).
  /// No upper bound (rolling substitutes are fine); submitScore enforces a
  /// floor of at least 5 attended per team (enforced in the DB too).
  Future<void> markAttendance({
    required String matchId,
    required String userId,
    required String teamId,
    required bool attended,
  }) async {
    final me = _uid;
    await SupabaseService.client.from(_matchPlayers).upsert({
      'match_id': matchId,
      'user_id': userId,
      'team_id': teamId,
      'attended': attended,
      'marked_by': me,
    }, onConflict: 'match_id,user_id');
  }

  // ---- Score submission (Task 6.3) ----

  /// A captain submits/re-submits their reported scoreline. Returns one of:
  /// 'completed' (both captains agree on the winner), 'disputed' (they report
  /// opposite winners), or 'awaiting_opponent' (other captain hasn't submitted).
  Future<String> submitScore({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    final result = await SupabaseService.client.rpc('submit_match_score', params: {
      'p_match_id': matchId,
      'p_home_score': homeScore,
      'p_away_score': awayScore,
    });
    return result as String;
  }

  /// The other captain confirms. Returns 'completed' or 'pending'.
  Future<String> confirmScore(String matchId) async {
    final result = await SupabaseService.client
        .rpc('confirm_match_score', params: {'p_match_id': matchId});
    return result as String;
  }

  // ---- Team rating (Task 7.2) ----

  /// ELOs of the active (attended) players for [teamId] in [matchId].
  Future<List<int>> fetchActivePlayerElos(
      String matchId, String teamId) async {
    final data = await SupabaseService.client
        .from(_matchPlayers)
        .select('users(elo)')
        .eq('match_id', matchId)
        .eq('team_id', teamId)
        .eq('attended', true);

    final elos = <int>[];
    for (final e in data as List) {
      final user = (e as Map<String, dynamic>)['users'];
      if (user is Map && user['elo'] != null) {
        elos.add((user['elo'] as num).toInt());
      }
    }
    return elos;
  }

  /// Convenience: the team rating (average active-player ELO) for [teamId] in
  /// [matchId], using the shared [EloEngine] rounding rules.
  Future<int> fetchTeamMatchRating(String matchId, String teamId) async {
    final elos = await fetchActivePlayerElos(matchId, teamId);
    return EloEngine.teamRating(elos);
  }

  // ---- Player behavior / sportsmanship ----

  /// Sportsmanship ratings the current user has submitted in [matchId],
  /// keyed by the rated player's user id (value is 'good' or 'bad').
  Future<Map<String, String>> fetchMyBehavior(String matchId) async {
    final uid = _uid;
    if (uid == null) return <String, String>{};
    final data = await SupabaseService.client
        .from(_behavior)
        .select('target_user_id, rating')
        .eq('match_id', matchId)
        .eq('rater_id', uid);

    final map = <String, String>{};
    for (final e in data as List) {
      final row = e as Map<String, dynamic>;
      final target = row['target_user_id'] as String?;
      final rating = row['rating'] as String?;
      if (target != null && rating != null) map[target] = rating;
    }
    return map;
  }

  /// Submit (or update) a sportsmanship rating for [targetUserId] in [matchId].
  /// [rating] is 'good' or 'bad'; [reason] is supplied by the UI for 'bad'.
  Future<void> submitBehavior({
    required String matchId,
    required String targetUserId,
    required String rating,
    String? reason,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');
    await SupabaseService.client.from(_behavior).upsert({
      'match_id': matchId,
      'rater_id': uid,
      'target_user_id': targetUserId,
      'rating': rating,
      'reason': reason,
    }, onConflict: 'match_id,rater_id,target_user_id');
  }
}
