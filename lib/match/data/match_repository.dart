import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_player_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/services/elo_engine.dart';
import 'package:footrank/services/supabase_service.dart';

class MatchRepository {
  static const _requests = 'match_requests';
  static const _matches = 'matches';
  static const _matchPlayers = 'match_players';

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
          'scheduled_at': scheduledAt.toIso8601String(),
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
        .select('*, teams(name, rating)')
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
        .select('*, teams(name, rating)')
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
    int withinMinutes = 30,
    int eloThreshold = 150,
  }) async {
    final from =
        scheduledAt.subtract(Duration(minutes: withinMinutes)).toIso8601String();
    final to =
        scheduledAt.add(Duration(minutes: withinMinutes)).toIso8601String();

    final data = await SupabaseService.client
        .from(_requests)
        .select('*, teams(name, rating)')
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

  /// A single match with both team names.
  Future<MatchModel> fetchMatchById(String matchId) async {
    final data = await SupabaseService.client
        .from(_matches)
        .select(
            '*, home_team:home_team_id(name), away_team:away_team_id(name)')
        .eq('id', matchId)
        .single();
    return MatchModel.fromJson(data);
  }

  /// Confirmed/completed matches involving the given team.
  Future<List<MatchModel>> fetchTeamMatches(String teamId) async {
    final data = await SupabaseService.client
        .from(_matches)
        .select(
            '*, home_team:home_team_id(name), away_team:away_team_id(name)')
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

  /// A captain submits/re-submits the final score (their side auto-confirms).
  Future<void> submitScore({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    await SupabaseService.client.rpc('submit_match_score', params: {
      'p_match_id': matchId,
      'p_home_score': homeScore,
      'p_away_score': awayScore,
    });
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

    return (data as List).map((e) {
      final user = e['users'] as Map<String, dynamic>?;
      return (user?['elo'] as int?) ?? EloEngine.startingElo;
    }).toList();
  }

  /// Team rating in a match = average ELO of its active players.
  Future<int> teamRatingForMatch(String matchId, String teamId) async {
    final elos = await fetchActivePlayerElos(matchId, teamId);
    return EloEngine.teamRating(elos);
  }

  // ---- Behavior ratings (Task 9.1 / 9.2) ----

  static const _behavior = 'behavior_reports';

  /// The current captain's behavior ratings for a match, keyed by target user.
  Future<Map<String, String>> fetchMyBehavior(String matchId) async {
    final uid = _uid;
    if (uid == null) return {};
    final data = await SupabaseService.client
        .from(_behavior)
        .select('target_user_id, rating')
        .eq('match_id', matchId)
        .eq('rater_id', uid);

    final map = <String, String>{};
    for (final e in data as List) {
      map[e['target_user_id'] as String] = e['rating'] as String;
    }
    return map;
  }

  /// Captain rates an opponent player: 'good' or 'bad' (+ optional reason).
  Future<void> submitBehavior({
    required String matchId,
    required String targetUserId,
    required String rating,
    String? reason,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');
    await SupabaseService.client.from(_behavior).insert({
      'match_id': matchId,
      'rater_id': uid,
      'target_user_id': targetUserId,
      'rating': rating,
      'reason': reason,
    });
  }
}
