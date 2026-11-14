import 'package:footrank/models/booking_models.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/venue_location.dart';
import 'package:footrank/services/supabase_service.dart';

/// Court booking flow: who books the court, "I booked it", and court changes
/// when a court is full. Every write goes through a server function that
/// checks the caller is a captain of the match.
class BookingRepository {
  static const _select =
      '*, home_team:home_team_id(name, logo_url, rating, wins, losses, draws), away_team:away_team_id(name, logo_url, rating, wins, losses, draws)';

  /// The other captain takes over the booking ("I'll book it").
  Future<void> claimBooking(String matchId) => SupabaseService.client
      .rpc('claim_booking', params: {'p_match_id': matchId});

  /// The Booker confirms the court is booked ("I booked it").
  Future<void> confirmBooked(String matchId) => SupabaseService.client
      .rpc('confirm_booked', params: {'p_match_id': matchId});

  /// "Court full": suggest another court.
  Future<void> suggestVenue({
    required String matchId,
    required String venueText,
    required VenueLocation location,
  }) =>
      SupabaseService.client.rpc('suggest_venue', params: {
        'p_match_id': matchId,
        'p_venue_text': venueText.trim(),
        ..._loc(location),
      });

  Future<void> respondVenue(String suggestionId, {required bool accept}) =>
      SupabaseService.client.rpc('respond_venue', params: {
        'p_suggestion_id': suggestionId,
        'p_accept': accept,
      });

  /// Decline the open suggestion and suggest another court instead.
  Future<void> counterVenue({
    required String suggestionId,
    required String venueText,
    required VenueLocation location,
  }) =>
      SupabaseService.client.rpc('counter_venue', params: {
        'p_suggestion_id': suggestionId,
        'p_venue_text': venueText.trim(),
        ..._loc(location),
      });

  Map<String, dynamic> _loc(VenueLocation l) => {
        'p_place_id': l.isManual ? null : l.placeId,
        'p_lat': l.lat,
        'p_lng': l.lng,
        'p_source': l.source,
      };

  /// The open "court full" suggestion on a match, if any.
  Future<VenueSuggestionModel?> fetchPendingSuggestion(String matchId) async {
    final data = await SupabaseService.client
        .from('venue_suggestions')
        .select()
        .eq('match_id', matchId)
        .eq('status', 'pending')
        .maybeSingle();
    return data == null ? null : VenueSuggestionModel.fromJson(data);
  }

  /// A team's court-booking reliability (0-100), null if unknown.
  Future<int?> fetchReliability(String? teamId) async {
    if (teamId == null) return null;
    final data = await SupabaseService.client
        .from('teams')
        .select()
        .eq('id', teamId)
        .maybeSingle();
    return data?['reliability_score'] as int?;
  }

  /// How many courts each team has suggested on this match (max 3 each).
  Future<int> countMySuggestions(String matchId, String teamId) async {
    final data = await SupabaseService.client
        .from('venue_suggestions')
        .select('id')
        .eq('match_id', matchId)
        .eq('suggested_by_team_id', teamId);
    return (data as List).length;
  }

  Future<List<MatchEventModel>> fetchEvents(String matchId) async {
    final data = await SupabaseService.client
        .from('match_events')
        .select()
        .eq('match_id', matchId)
        .order('created_at');
    return (data as List)
        .map((e) => MatchEventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Upcoming matches the signed-in captain still has to book, soonest
  /// deadline first.
  Future<List<MatchModel>> fetchMyUnbookedMatches() async {
    final uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) return const [];
    final teams = await SupabaseService.client
        .from('teams')
        .select('id')
        .eq('captain_id', uid);
    final ids = (teams as List).map((t) => t['id'] as String).toList();
    if (ids.isEmpty) return const [];
    final data = await SupabaseService.client
        .from('matches')
        .select(_select)
        .inFilter('booker_team_id', ids)
        .eq('status', 'confirmed')
        .eq('court_booking_status', 'not_booked')
        .order('booking_deadline_at');
    return (data as List)
        .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
