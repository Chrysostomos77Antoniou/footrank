import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/services/supabase_service.dart';

class RankingRepository {
  /// Players must have played at least this many matches to be ranked.
  static const int minMatches = 5;

  /// Ranked players (>= [minMatches] matches), ordered by ELO (desc),
  /// optionally filtered by position.
  Future<List<UserModel>> fetchPlayers({String? position}) async {
    var query = SupabaseService.client
        .from('users')
        .select()
        .gte('matches_played', minMatches);
    if (position != null) {
      query = query.eq('position', position);
    }
    final data = await query.order('elo', ascending: false);
    return (data as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Teams ordered by rating (desc), optionally filtered by city.
  Future<List<TeamModel>> fetchTeams({String? city}) async {
    var query = SupabaseService.client.from('teams').select();
    if (city != null && city.trim().isNotEmpty) {
      query = query.ilike('city', city.trim());
    }
    final data = await query.order('rating', ascending: false);
    return (data as List)
        .map((e) => TeamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
