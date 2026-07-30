import 'package:footrank/models/court_model.dart';
import 'package:footrank/services/supabase_service.dart';

class CourtRepository {
  static const _courts = 'courts';
  static const _requestPicks = 'match_request_court_picks';

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

  /// Every active court across all cities, for the "Browse Courts" page.
  Future<List<CourtModel>> fetchAllCourts() async {
    final data = await SupabaseService.client
        .from(_courts)
        .select('id, name, city, address, image_url')
        .eq('active', true)
        .order('city')
        .order('name');

    return (data as List)
        .map((e) => CourtModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Saves a captain's 3 ranked court choices (index 0 = 1st choice) for a
  /// newly-created match request. Browsing (fetchCityRequests) and accepting
  /// (acceptMatchRequest) both read these back to resolve a suggested court.
  Future<void> insertRequestCourtPicks(
    String requestId,
    List<String> courtIds,
  ) async {
    await SupabaseService.client.from(_requestPicks).insert([
      for (var i = 0; i < courtIds.length; i++)
        {'request_id': requestId, 'court_id': courtIds[i], 'rank': i + 1},
    ]);
  }

  /// Ranked court picks (rank 1..3) for a single request, if any.
  Future<List<String>> fetchPicksForRequest(String requestId) async {
    final map = await fetchPicksForRequests([requestId]);
    return map[requestId] ?? const [];
  }

  /// Batch fetch: request id -> its ranked court ids (rank 1..3 order).
  /// Used to score court compatibility across many candidate opponents at
  /// once instead of one query per candidate.
  Future<Map<String, List<String>>> fetchPicksForRequests(
    List<String> requestIds,
  ) async {
    if (requestIds.isEmpty) return {};
    final data = await SupabaseService.client
        .from(_requestPicks)
        .select('request_id, court_id, rank')
        .inFilter('request_id', requestIds)
        .order('rank');

    final map = <String, List<String>>{};
    for (final e in data as List) {
      final row = e as Map<String, dynamic>;
      final reqId = row['request_id'] as String;
      (map[reqId] ??= []).add(row['court_id'] as String);
    }
    return map;
  }

  /// Batch fetch: request id -> its ranked court picks (rank 1..3 order),
  /// with full court details -- used to show captains which courts each
  /// open request picked, not just score compatibility.
  Future<Map<String, List<CourtModel>>> fetchPicksWithCourtsForRequests(
    List<String> requestIds,
  ) async {
    if (requestIds.isEmpty) return {};
    final data = await SupabaseService.client
        .from(_requestPicks)
        .select('request_id, rank, courts(id, name, city, address, image_url)')
        .inFilter('request_id', requestIds)
        .order('rank');

    final map = <String, List<CourtModel>>{};
    for (final e in data as List) {
      final row = e as Map<String, dynamic>;
      final court = row['courts'] as Map<String, dynamic>?;
      if (court == null) continue;
      final reqId = row['request_id'] as String;
      (map[reqId] ??= []).add(CourtModel.fromJson(court));
    }
    return map;
  }
}
