import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_player_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/services/elo_engine.dart';
import 'package:footrank/services/supabase_service.dart';

class MatchRepository {
  static const _requests = 'match_requests';
  static const _matches = 'matches';
  static const _matchPlayers = 'match_players';

  /// Default discovery windows, shared by findOpponents and findAllOpponents so
  /// both code paths use identical matching rules.
  static const int defaultWithinMinutes = 30;
  static const int defaultEloThreshold = 150;

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// Creates a match request for the captain's team.
  Future<MatchRequestModel> createMatchRequest({
    required String teamId,
    required String city,
    required DateTime scheduledAt,
    required String matchType,
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

    return MatchRequestModel.fromJson(inserted);
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
  Future<List<MatchRequestModel>> findOpponents({
    required String myTeamId,
    required int myTeamRating,
    required String city,
    required DateTime scheduledAt,
    int withinMinutes = defaultWithinMinutes,
    int eloThreshold = defaultEloThreshold,
  }) async {
    // Bounds must be expressed in UTC to match how scheduled_at is stored
    // (createMatchRequest writes scheduledAt.toUtc()). Without .toUtc() the
    // window is offset by the device's UTC offset, silently dropping valid
    // opponents.
    final from = scheduledAt
        .subtract(Duration(minutes: withinMinutes))
        .toUtc()
        .toIso8601String();
    final to = scheduledAt
        .add(Duration(minutes: withinMinutes))
        .toUtc()
        .toIso8601String();

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
    return candidates.where((r) {
      final rating = r.teamRating;
      if (rating == null) return false;
      return (rating - myTeamRating).abs() <= eloThreshold;
    }).toList();
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

  /// ALL open ('searching') requests from OTHER teams — a simple, always-visible
  /// list of opponents to confirm a match against. No time/rating windowing, so
  /// nothing is ever silently hidden.
  Future<List<MatchRequestModel>> fetchOpenOpponentRequests(
      String myTeamId) async {
    final data = await SupabaseService.client
        .from(_requests)
        .select('*, teams(name, rating, logo_url)')
        .eq('status', 'searching')
        .neq('team_id', myTeamId)
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
      // An opponent qualifies if it matches ANY of the team's open requests.
      final matches =
          myRequests.any((ref) => _matchesReference(ref, opponent));
      if (matches && seen.add(opponent.id)) {
        all.add(opponent);
      }
    }
    return all;
  }

  // ---- Accept / Reject (Task 5.3) ----

  /// Opponent captain accepts [requestId]; creates a match and confirms the
  /// request atomically (via DB function). Returns the new match id.
  Future<String> acceptMatchRequest({
    required String requestId,
    required String awayTeamId,
  }) async {
    final result = await SupabaseService.client.rpc(
      'accept_match_request',
      params: {
        'p_request_id': requestId,
        'p_away_team_id': awayTeamId,
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
            '*, home_team:home_team_id(name, logo_url, rating, wins, losses, draws), away_team:away_team_id(name, logo_url, rating, wins, losses, draws)')
        .eq('id', matchId)
        .single();
    return MatchModel.fromJson(data);
  }

  /// Confirmed/completed matches involving the given team.
  Future<List<MatchModel>> fetchTeamMatches(String teamId) async {
    final data = await SupabaseService.client
        .from(_matches)
        .select(
            '*, home_team:home_team_id(name, logo_url, rating, wins, losses, draws), away_team:away_team_id(name, logo_url, rating, wins, losses, draws)')
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

  /// Opposing captain marks a player attended / not attended (upsert).
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
