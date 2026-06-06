class MatchModel {
  final String id;
  final String? requestId;
  final String homeTeamId;
  final String awayTeamId;
  final String city;
  final DateTime scheduledAt;
  final String matchType;
  final String format;
  final String status; // confirmed | completed | cancelled
  final int? homeScore;
  final int? awayScore;
  final String? scoreProposedBy;
  final bool homeConfirmed;
  final bool awayConfirmed;
  final DateTime createdAt;

  // Optional joined team names
  final String? homeTeamName;
  final String? awayTeamName;

  const MatchModel({
    required this.id,
    this.requestId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.city,
    required this.scheduledAt,
    required this.matchType,
    required this.format,
    required this.status,
    this.homeScore,
    this.awayScore,
    this.scoreProposedBy,
    this.homeConfirmed = false,
    this.awayConfirmed = false,
    required this.createdAt,
    this.homeTeamName,
    this.awayTeamName,
  });

  bool get hasScore => homeScore != null && awayScore != null;

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    final home = json['home_team'] as Map<String, dynamic>?;
    final away = json['away_team'] as Map<String, dynamic>?;
    return MatchModel(
      id: json['id'] as String,
      requestId: json['request_id'] as String?,
      homeTeamId: json['home_team_id'] as String,
      awayTeamId: json['away_team_id'] as String,
      city: json['city'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      matchType: json['match_type'] as String,
      format: json['format'] as String,
      status: json['status'] as String,
      homeScore: json['home_score'] as int?,
      awayScore: json['away_score'] as int?,
      scoreProposedBy: json['score_proposed_by'] as String?,
      homeConfirmed: (json['home_confirmed'] as bool?) ?? false,
      awayConfirmed: (json['away_confirmed'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      homeTeamName: home?['name'] as String?,
      awayTeamName: away?['name'] as String?,
    );
  }
}
