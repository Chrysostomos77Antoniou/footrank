import 'package:footrank/models/venue_location.dart';

/// A "court full" suggestion for another court on a confirmed match.
class VenueSuggestionModel {
  final String id;
  final String matchId;
  final String suggestedByTeamId;
  final String venueText;
  final VenueLocation? location;
  final String status; // pending | accepted | declined | superseded
  final DateTime createdAt;

  const VenueSuggestionModel({
    required this.id,
    required this.matchId,
    required this.suggestedByTeamId,
    required this.venueText,
    this.location,
    required this.status,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';

  factory VenueSuggestionModel.fromJson(Map<String, dynamic> json) =>
      VenueSuggestionModel(
        id: json['id'] as String,
        matchId: json['match_id'] as String,
        suggestedByTeamId: json['suggested_by_team_id'] as String,
        venueText: json['venue_text'] as String,
        location: VenueLocation.fromJson(json),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// One line of a match's booking timeline.
class MatchEventModel {
  final String id;
  final String? teamId;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const MatchEventModel({
    required this.id,
    this.teamId,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  factory MatchEventModel.fromJson(Map<String, dynamic> json) =>
      MatchEventModel(
        id: json['id'] as String,
        teamId: json['team_id'] as String?,
        type: json['type'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// Plain-language line, e.g. "Court 101 suggested".
  String describe({String? Function(String? teamId)? teamName}) {
    final venue = payload['venue'] as String?;
    final who = teamName?.call(teamId) ?? payload['team'] as String?;
    switch (type) {
      case 'confirmed':
        return 'Match confirmed. ${payload['booker'] ?? 'One team'} books the court';
      case 'booker_claimed':
        return '${who ?? 'The other team'} took over the booking';
      case 'booked':
        return 'Court booked${venue == null ? '' : ': $venue'}';
      case 'venue_suggested':
        return '${venue ?? 'A court'} suggested${who == null ? '' : ' by $who'}';
      case 'venue_accepted':
        return '${venue ?? 'Court'} accepted';
      case 'venue_declined':
        return '${venue ?? 'Court'} declined';
      case 'reminder_sent':
        return 'Booking reminder sent';
      case 'auto_cancelled':
        return 'Match cancelled';
      default:
        return type;
    }
  }
}
