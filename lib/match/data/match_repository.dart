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

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// Creates a match request for the captain's team. [venueText] is the
  /// venue name exactly as the captain typed it -- it is shown verbatim to
  /// browsing captains and copied onto the match once a proposal is accepted.
  /// The server validates it (length, no links/phone numbers, basic
  /// profanity) and enforces the daily request limit; see [friendlyError] for
  /// the messages those rejections map to.
  Future<MatchRequestModel> createMatchRequest({
    required String teamId,
    required String city,
    required DateTime scheduledAt,
    required String matchType,
    required String venueText,
    String format = '5v5',
    List<String>? rosterUserIds,
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
          'venue_text': venueText.trim(),
          if (rosterUserIds != null) 'roster_user_ids': rosterUserIds,
        })
        .select('*, teams(name)')
        .single();

    return MatchRequestModel.fromJson(inserted);
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
  /// [date] narrows to requests scheduled on that calendar day; [timeOfDay]
  /// (minutes since midnight, local) narrows to requests within an hour of
  /// that time on any day; [matchType] narrows to 'casual' or 'ranked'. All
  /// are optional except [city]. Each result carries the venue text the
  /// requesting captain typed (see [MatchRequestModel.venueText]) so captains
  /// can see where a match would be played before proposing.
  Future<List<MatchRequestModel>> fetchCityRequests({
    required String city,
    required String excludeTeamId,
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
    return requests;
  }

  // ---- Propose / Accept / Reject (browse-and-propose flow) ----

  /// Any member of [teamId] can propose against an open [requestId] --
  /// proposing isn't captain-restricted, only accepting/rejecting is. Does
  /// NOT lock the request -- it stays 'searching' (and other teams can
  /// still propose) until the request's own captain accepts one proposal.
  ///
  /// [venueText] is an optional venue the proposing team would rather play
  /// at; the request's captain sees it and decides when accepting. It is only
  /// sent when it has text, so a proposal without one behaves exactly as it
  /// always did.
  Future<String> proposeMatch({
    required String requestId,
    required String teamId,
    List<String>? rosterUserIds,
    String? venueText,
  }) async {
    final venue = venueText?.trim();
    final venueParam = <String, dynamic>{
      if (venue != null && venue.isNotEmpty) 'p_venue_text': venue,
    };
    if (rosterUserIds != null) {
      final result = await SupabaseService.client.rpc(
        'propose_match_with_roster',
        params: {
          'p_request_id': requestId,
          'p_team_id': teamId,
          'p_roster_user_ids': rosterUserIds,
          ...venueParam,
        },
      );
      return result as String;
    }
    final result = await SupabaseService.client.rpc(
      'propose_match',
      params: {
        'p_request_id': requestId,
        'p_team_id': teamId,
        ...venueParam,
      },
    );
    return result as String;
  }

  /// Captain / vice-captain sets the team's roster (who is playing) for a
  /// confirmed match. Allowed until kick-off; needs at least 5 players.
  Future<void> setMatchRoster({
    required String matchId,
    required String teamId,
    required List<String> userIds,
  }) =>
      SupabaseService.client.rpc('set_match_roster', params: {
        'p_match_id': matchId,
        'p_team_id': teamId,
        'p_user_ids': userIds,
      });

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
            '*, match_requests(city, scheduled_at, match_type, format, venue_text, teams(name, rating, logo_url))')
        .eq('proposing_team_id', teamId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => MatchProposalModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Accept / Reject (Task 5.3) ----

  /// Opponent captain accepts [requestId]; creates a match and confirms the
  /// request atomically (via DB function). The match inherits the venue the
  /// requesting captain typed. [myRequestId] is the accepting captain's own
  /// reference request, if they have one (only used by the legacy court-pick
  /// flow for old requests). Returns the new match id.
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

  /// The requesting (home) captain corrects where the match is played. The
  /// opponent captain is notified by the server. Throws on validation
  /// failures (see [friendlyError]).
  Future<void> updateMatchVenue({
    required String matchId,
    required String venueText,
  }) async {
    await SupabaseService.client.rpc('update_match_venue', params: {
      'p_match_id': matchId,
      'p_venue_text': venueText.trim(),
    });
  }

  /// Flags a user-entered venue name (on a request, on a match, or suggested
  /// on a proposal) for admin review -- e.g. fake or inappropriate text.
  /// Exactly one id is passed. A proposal's venue can only be reported by the
  /// captain who received that proposal.
  Future<void> reportVenue({
    String? requestId,
    String? matchId,
    String? proposalId,
  }) async {
    assert(
        [requestId, matchId, proposalId].where((e) => e != null).length == 1,
        'pass exactly one of requestId / matchId / proposalId');
    await SupabaseService.client.rpc('report_venue', params: {
      'p_request_id': requestId,
      'p_match_id': matchId,
      if (proposalId != null) 'p_proposal_id': proposalId,
    });
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

  // ---- Roster / attendance ----

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
