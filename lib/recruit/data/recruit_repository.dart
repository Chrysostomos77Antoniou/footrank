import 'package:footrank/models/recruitment_model.dart';
import 'package:footrank/services/supabase_service.dart';

/// The current user's request on a post: its id (to cancel) and status.
typedef MyRequest = ({String id, String status});

class RecruitRepository {
  static const positions = ['Goalkeeper', 'Defender', 'Midfielder', 'Forward'];

  static const _posts = 'team_recruitments';
  // Explicit team columns: never `teams(*)`, so nothing private (invite code)
  // is served to every viewer of the list.
  static const _cols = 'id,team_id,spots,accepted,position,note,expires_at,'
      'teams(id,name,city,logo_url,captain_id,rating,wins,losses,draws,'
      'created_at,disbanded_at)';

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// Open posts from teams the user is not already in.
  Future<List<RecruitmentModel>> fetchOpen() async {
    final uid = _uid;
    if (uid == null) return [];
    final data = await SupabaseService.client
        .from(_posts)
        .select(_cols)
        .eq('status', 'open')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    final mine = await SupabaseService.client
        .from('team_members')
        .select('team_id')
        .eq('user_id', uid);
    final myTeamIds = {for (final r in mine as List) r['team_id'] as String};
    return (data as List)
        .map((e) => RecruitmentModel.fromJson(e as Map<String, dynamic>))
        .where((p) =>
            !myTeamIds.contains(p.teamId) && !(p.team?.isDisbanded ?? false))
        .toList();
  }

  /// The user's own requests on posts, keyed by post id.
  Future<Map<String, MyRequest>> fetchMyRequests() async {
    final uid = _uid;
    if (uid == null) return {};
    final data = await SupabaseService.client
        .from('team_join_requests')
        .select('id,status,recruitment_id')
        .eq('user_id', uid)
        .not('recruitment_id', 'is', null);
    return {
      for (final r in data as List)
        r['recruitment_id'] as String:
            (id: r['id'] as String, status: r['status'] as String),
    };
  }

  /// The team's open post, or null (captain view).
  Future<RecruitmentModel?> fetchOpenForTeam(String teamId) async {
    final data = await SupabaseService.client
        .from(_posts)
        .select(_cols)
        .eq('team_id', teamId)
        .eq('status', 'open')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .maybeSingle();
    return data == null ? null : RecruitmentModel.fromJson(data);
  }

  Future<void> create({
    required String teamId,
    required int spots,
    String? position,
    String? note,
  }) =>
      SupabaseService.client.rpc('create_team_recruitment', params: {
        'p_team_id': teamId,
        'p_spots': spots,
        'p_position': position,
        'p_note': note,
      });

  Future<void> close(String recruitmentId) => SupabaseService.client
      .rpc('close_team_recruitment', params: {'p_recruitment_id': recruitmentId});

  Future<void> requestJoin(String recruitmentId) =>
      SupabaseService.client.rpc('request_join_recruitment',
          params: {'p_recruitment_id': recruitmentId});

  Future<void> cancelRequest(String requestId) => SupabaseService.client
      .rpc('cancel_join_request', params: {'p_request_id': requestId});
}
