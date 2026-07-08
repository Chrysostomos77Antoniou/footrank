import 'package:footrank/models/court_model.dart';
import 'package:footrank/services/supabase_service.dart';

class CourtRepository {
  static const _courts = 'courts';
  static const _picks = 'match_court_picks';

  /// Active courts in [city] a captain can choose from. Deliberately selects
  /// only name/address/image — never phone (see [CourtModel]).
  Future<List<CourtModel>> fetchCourtsForCity(String city) async {
    final data = await SupabaseService.client
        .from(_courts)
        .select('id, name, city, address, image_url')
        .ilike('city', city.trim())
        .eq('active', true)
        .order('name');

    return (data as List)
        .map((e) => CourtModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// This team's already-submitted ranked picks for [matchId], if any
  /// (ordered by rank 1..3). Empty when the captain hasn't submitted yet.
  Future<List<String>> fetchMyPicks(String matchId, String teamId) async {
    final data = await SupabaseService.client
        .from(_picks)
        .select('court_id')
        .eq('match_id', matchId)
        .eq('team_id', teamId)
        .order('rank');

    return (data as List)
        .map((e) => (e as Map<String, dynamic>)['court_id'] as String)
        .toList();
  }

  /// Submits this captain's 3 ranked court choices (index 0 = 1st choice).
  /// Once both captains have submitted, the DB resolves a suggested court
  /// automatically (see submit_court_picks()).
  Future<void> submitCourtPicks(String matchId, List<String> courtIds) async {
    await SupabaseService.client.rpc('submit_court_picks', params: {
      'p_match_id': matchId,
      'p_court_ids': courtIds,
    });
  }
}
