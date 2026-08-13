/// A logged captain-initiated cancellation -- `cancel_match`/
/// `cancel_confirmed_match` delete the underlying `matches` row (see their
/// comments), so this table is the only surviving record that the event
/// happened. Team names are denormalized at write time so this stays
/// readable even if a team is later disbanded.
class MatchCancellationModel {
  final String id;
  final String homeTeamName;
  final String awayTeamName;
  final String cancelledByTeamId;
  final String cancelledByTeamName;
  final String city;
  final DateTime scheduledAt;
  final bool penalized;
  final DateTime createdAt;

  const MatchCancellationModel({
    required this.id,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.cancelledByTeamId,
    required this.cancelledByTeamName,
    required this.city,
    required this.scheduledAt,
    required this.penalized,
    required this.createdAt,
  });

  factory MatchCancellationModel.fromJson(Map<String, dynamic> json) {
    final homeId = json['home_team_id'] as String;
    final cancelledById = json['cancelled_by_team_id'] as String;
    final homeName = json['home_team_name'] as String;
    final awayName = json['away_team_name'] as String;
    return MatchCancellationModel(
      id: json['id'] as String,
      homeTeamName: homeName,
      awayTeamName: awayName,
      cancelledByTeamId: cancelledById,
      cancelledByTeamName: cancelledById == homeId ? homeName : awayName,
      city: json['city'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      penalized: json['penalized'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
