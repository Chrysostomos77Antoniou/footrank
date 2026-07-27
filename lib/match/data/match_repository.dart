import 'package:footrank/match/data/court_repository.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_player_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/services/elo_engine.dart';
import 'package:footrank/services/supabase_service.dart';

class MatchRepository {
  static const _requests = 'match_requests';
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

  /// Creates a match request for the captain's team, with exactly 3 ranked
  /// court choices (index 0 = 1st choice) in [city]. Those picks drive both
  /// opponent matching ([findOpponents]) and, once accepted, the automatic
  /// suggested-court resolution.
  Future<MatchRequestModel> createMatchRequest({
    required String teamId,
    required String city,
    required DateTime scheduledAt,
    required String matchType,
    required List<String> courtIds,
    String format = '5v5',
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');
    if (courtIds.length != 3 || courtIds.toSet().length != 3) {
      throw ArgumentError('Pick exactly 3 different courts, ranked in order of preference');
    }

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
    await _courtRepo.insertRequestCourtPicks(request.id, courtIds);
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

  /// True when [opponent] matches [ref] under the same city/time/ELO windows
  /// used by [findOpponents]. Shared so server-side and client-side discovery
  /// agree on what counts as a match.
  bool _matchesReference(
    MatchRequestModel ref,
    MatchRequestModel opponent, {
    int withinMinutes = defaultWithinMinutes,
    int eloThreshold = defaultEloThreshold,
  }) {
    // Same city (case-insensitive, trimmed) — mirrors ilike(city.trim()).
    if (opponent.city.trim().toLowerCase() != ref.city.trim().toLowerCase()) {
      return false;
    }

    // Scheduled time within +/- withinMinutes of the reference.
    final diff = opponent.scheduledAt.difference(ref.scheduledAt).inMinutes.abs();
    if (diff > withinMinutes) return false;

    // ELO proximity against the reference team's rating.
    final myRating = ref.teamRating ?? 1500;
    final oppRating = opponent.teamRating;
    if (oppRating == null) return false;
    return (oppRating - myRating).abs() <= eloThreshold;
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

  /// Open ('searching') requests from OTHER teams whose match time hasn't
  /// already passed — a simple, always-visible list of opponents to confirm a
  /// match against. Stale past requests are dropped server-side; no upper bound,
  /// so legitimately far-future matches still appear.
  Future<List<MatchRequestModel>> fetchOpenOpponentRequests(
      String myTeamId) async {
    final data = await SupabaseService.client
        .from(_requests)
        .select('*, teams(name, rating, logo_url)')
        .eq('status', 'searching')
        .neq('team_id', myTeamId)
        // A match can't be played retroactively, so skip requests already in the
        // past (the stale records that pile up without a cleanup job).
        .gte(
          'scheduled_at',
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        )
        .order('scheduled_at');

    return (data as List)
        .map((e) => MatchRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Aggregates matchable opponents across ALL of the team's open requests,
  /// de-duplicated by request id. Used to surface opponents directly on the
  /// Matches screen (no manual "Find Opponents" step needed).
  ///
  /// Uses exactly TWO queries regardless of how many open requests the team has
  /// (one for the team's own 'searching' requests, one for all open opponent
  /// requests) and applies the same city/time/ELO windows as [findOpponents]
  /// client-side. This replaces the previous 1 + N serialized query pattern.
  Future<List<MatchRequestModel>> findAllOpponents(String teamId) async {
    final myRequests = await fetchSearchingRequests(teamId);
    if (myRequests.isEmpty) return <MatchRequestModel>[];

    final opponentRequests = await fetchOpenOpponentRequests(teamId);

    final seen = <String>{};
    final all = <MatchRequestModel>[];
    for (final opponent in opponentRequests) {
      // An opponent qualifies if it matches ANY of the team's open requests —
      // tag it with the FIRST one that matched, so acceptMatchRequest() knows
      // whose court picks to resolve the suggested court against.
      final ref = myRequests
          .cast<MatchRequestModel?>()
          .firstWhere((r) => _matchesReference(r!, opponent), orElse: () => null);
      if (ref != null && seen.add(opponent.id)) {
        all.add(opponent.copyWith(matchedFromRequestId: ref.id));
      }
    }
    return all;
  }

  // ---- Accept / Reject (Task 5.3) ----

  /// Opponent captain accepts [requestId]; creates a match and confirms the
  /// request atomically (via DB function). [myRequestId] is the accepting
  /// captain's own reference request — its ranked court picks are compared
  /// against the accepted request's to resolve a suggested court immediately.
  /// Returns the new match id.
  Future<String> acceptMatchRequest({
    required String requestId,
    required String awayTeamId,
    required String myRequestId,
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

  /// Reschedule a not-yet-completed match (either captain).
  Future<void> rescheduleMatch(String matchId, DateTime scheduledAt) =>
      SupabaseService.client.rpc('reschedule_match', params: {
        'p_match_id': matchId,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      });

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
