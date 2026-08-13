import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/models/match_cancellation_model.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/profile/data/profile_repository.dart'
    show normalizeImageExt, imageContentType;
import 'package:footrank/services/supabase_service.dart';

/// Backs the admin web panel. Reads rely on this app's already-open
/// `SELECT` policies (any authenticated user can read courts/matches/
/// requests/teams/users -- verified during the security assessment
/// earlier this project), so this repository does not need its own
/// read RPCs. Every write goes through an `admin_*` RPC that checks
/// `is_admin` on the caller server-side -- the real authorization
/// boundary, not just this panel hiding the button.
class AdminRepository {
  SupabaseClient get _client => SupabaseService.client;

  /// Whether the signed-in user is allowed in here at all.
  Future<bool> isCurrentUserAdmin() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await _client
        .from('users')
        .select('is_admin')
        .eq('id', uid)
        .maybeSingle();
    return (row?['is_admin'] as bool?) ?? false;
  }

  // ---- Courts ----

  static const _courtColumns =
      'id,name,city,address,phone,website,hours,image_url,active,sort_order';

  Future<List<AdminCourtModel>> fetchAllCourts() async {
    final data = await _client
        .from('courts')
        .select(_courtColumns)
        .order('city')
        .order('sort_order', nullsFirst: false)
        .order('name');
    return (data as List)
        .map((e) => AdminCourtModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AdminCourtModel> upsertCourt(
    AdminCourtModel court, {
    bool isNew = false,
  }) async {
    final data = await _client.rpc(
      'admin_upsert_court',
      params: {
        'p_id': isNew ? null : court.id,
        'p_name': court.name,
        'p_city': court.city,
        'p_address': court.address,
        'p_phone': court.phone,
        'p_website': court.website,
        'p_hours': court.hours,
        'p_image_url': court.imageUrl,
        'p_sort_order': court.sortOrder,
        'p_active': court.active,
      },
    );
    return AdminCourtModel.fromJson(data as Map<String, dynamic>);
  }

  /// Uploads a court photo (picked from the admin's computer or phone
  /// gallery) to the `court-photos` bucket and returns its public URL.
  /// Storage RLS restricts writes on this bucket to `is_admin` accounts
  /// (verified live against the real Storage API, not just the policy
  /// text) -- same authorization boundary as every admin_* RPC.
  Future<String> uploadCourtImage(List<int> bytes, String fileExt) async {
    final ext = normalizeImageExt(fileExt);
    final path = 'admin/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage
        .from('court-photos')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: imageContentType(ext),
            upsert: false,
          ),
        );
    return _client.storage.from('court-photos').getPublicUrl(path);
  }

  // ---- Matches / requests / proposals ----

  static const _matchJoins =
      '*, home_team:home_team_id(name, logo_url, rating, wins, losses, draws), '
      'away_team:away_team_id(name, logo_url, rating, wins, losses, draws)';

  Future<List<MatchModel>> fetchAllMatches({
    String? city,
    String? status,
  }) async {
    var query = _client.from('matches').select(_matchJoins);
    if (city != null) query = query.ilike('city', city);
    if (status != null) query = query.eq('status', status);
    final data = await query.order('scheduled_at', ascending: false).limit(200);
    return (data as List)
        .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MatchModel>> fetchDisputedMatches() async {
    final data = await _client
        .from('matches')
        .select(_matchJoins)
        .eq('score_disputed', true)
        .order('scheduled_at', ascending: false);
    return (data as List)
        .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MatchRequestModel>> fetchAllOpenRequests() async {
    final data = await _client
        .from('match_requests')
        .select('*, teams(name, rating, logo_url)')
        .eq('status', 'searching')
        .order('scheduled_at');
    return (data as List)
        .map((e) => MatchRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MatchProposalModel>> fetchAllPendingProposals() async {
    final data = await _client
        .from('match_request_proposals')
        .select(
          '*, teams(name, rating, logo_url), match_requests(city, scheduled_at, match_type, format, teams(name, rating, logo_url))',
        )
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => MatchProposalModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolveDispute({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) => _client.rpc(
    'admin_resolve_dispute',
    params: {
      'p_match_id': matchId,
      'p_home_score': homeScore,
      'p_away_score': awayScore,
    },
  );

  Future<void> forceCancelMatch(String matchId, {String? reason}) =>
      _client.rpc(
        'admin_force_cancel_match',
        params: {'p_match_id': matchId, 'p_reason': reason},
      );

  /// Captain-initiated cancellations delete the `matches` row outright (see
  /// `cancel_match`/`cancel_confirmed_match` -- that frees the slot for the
  /// "no overlapping commitment" check), so nothing else records that a
  /// cancellation happened. This RPC reads the audit log those functions
  /// write to instead, gated on `is_admin` server-side like every other
  /// admin_* call.
  Future<List<MatchCancellationModel>> fetchMatchCancellations() async {
    final data = await _client.rpc('admin_fetch_match_cancellations');
    return (data as List)
        .map(
          (e) => MatchCancellationModel.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  // ---- Teams ----

  Future<List<TeamModel>> fetchAllTeams() async {
    final data = await _client
        .from('teams')
        .select()
        .isFilter('disbanded_at', null)
        .order('rating', ascending: false);
    return (data as List)
        .map((e) => TeamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Users / moderation ----

  static const _userColumns =
      'id,name,username,city,position,elo,reliability,'
      'behavior_positive,behavior_negative,matches_played,avatar_url,'
      'dispute_count,flagged,created_at';

  Future<List<UserModel>> fetchAllUsers() async {
    final data = await _client
        .from('users')
        .select(_userColumns)
        .order('name')
        .limit(300);
    return (data as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UserModel>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final data = await _client
        .from('users')
        .select(_userColumns)
        .or('name.ilike.%$q%,username.ilike.%$q%')
        .order('name')
        .limit(50);
    return (data as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UserModel>> fetchFlaggedUsers() async {
    final data = await _client
        .from('users')
        .select(_userColumns)
        .eq('flagged', true)
        .order('dispute_count', ascending: false);
    return (data as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Matches where [userId]'s team was ever involved in a scoring dispute --
  /// there's no separate per-user dispute log table, so this is derived
  /// through the user's team history. Filters on `dispute_rounds > 0` rather
  /// than `score_disputed` -- the latter resets to false once a dispute
  /// auto-resolves (see submit_match_score's 2-round resolution), so it
  /// would silently hide every dispute that isn't currently stuck.
  Future<List<MatchModel>> fetchDisputeHistory(String userId) async {
    final teamIds = await _client
        .from('team_members')
        .select('team_id')
        .eq('user_id', userId);
    final ids = (teamIds as List)
        .map((e) => (e as Map<String, dynamic>)['team_id'] as String)
        .toList();
    if (ids.isEmpty) return [];

    final data = await _client
        .from('matches')
        .select(_matchJoins)
        .or(
          'home_team_id.in.(${ids.join(',')}),away_team_id.in.(${ids.join(',')})',
        )
        .gt('dispute_rounds', 0)
        .order('scheduled_at', ascending: false);
    return (data as List)
        .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setUserModeration({
    required String userId,
    required bool flagged,
    required int reliability,
  }) => _client.rpc(
    'admin_set_user_moderation',
    params: {
      'p_user_id': userId,
      'p_flagged': flagged,
      'p_reliability': reliability,
    },
  );
}
