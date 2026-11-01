import 'package:footrank/models/court_model.dart';
import 'package:footrank/services/supabase_service.dart';

/// Read-only access to the courts directory ("Courts" on the home screen).
///
/// Match requests no longer reference courts: captains type the venue name
/// themselves (see `MatchRepository.createMatchRequest`), so nothing in the
/// match flow reads from this list.
class CourtRepository {
  static const _courts = 'courts';

  /// Every active court across all cities, for the "Browse Courts" page.
  /// Deliberately selects only name/address/image -- never phone (see
  /// [CourtModel]).
  Future<List<CourtModel>> fetchAllCourts() async {
    final data = await SupabaseService.client
        .from(_courts)
        .select('id, name, city, address, image_url')
        .eq('active', true)
        .order('city')
        .order('sort_order', nullsFirst: false)
        .order('name');

    return (data as List)
        .map((e) => CourtModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
