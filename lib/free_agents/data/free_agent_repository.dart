import 'package:footrank/models/user_model.dart';
import 'package:footrank/services/supabase_service.dart';

class FreeAgentFilter {
  final String? position; // null = any
  final int minElo;
  final int minReliability;

  const FreeAgentFilter({
    this.position,
    this.minElo = 0,
    this.minReliability = 0,
  });

  FreeAgentFilter copyWith({
    String? position,
    bool clearPosition = false,
    int? minElo,
    int? minReliability,
  }) {
    return FreeAgentFilter(
      position: clearPosition ? null : (position ?? this.position),
      minElo: minElo ?? this.minElo,
      minReliability: minReliability ?? this.minReliability,
    );
  }
}

class FreeAgentRepository {
  static const _view = 'free_agents';

  /// Returns users not on any team, applying the given filters.
  Future<List<UserModel>> fetchFreeAgents([
    FreeAgentFilter filter = const FreeAgentFilter(),
  ]) async {
    final currentUserId = SupabaseService.client.auth.currentUser?.id;

    var query = SupabaseService.client.from(_view).select();

    if (filter.position != null) {
      query = query.eq('position', filter.position!);
    }
    if (filter.minElo > 0) {
      query = query.gte('elo', filter.minElo);
    }
    if (filter.minReliability > 0) {
      query = query.gte('reliability', filter.minReliability);
    }

    final data = await query.order('elo', ascending: false);

    return (data as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .where((u) => u.id != currentUserId) // exclude self
        .toList();
  }
}
