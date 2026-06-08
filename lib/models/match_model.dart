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
  final bool homeOk; // home captain confirmed the fixture
  final bool awayOk; // away captain confirmed the fixture
  final int? homeReportH; // home captain's reported home score
  final int? homeReportA; // home captain's reported away score
  final int? awayReportH; // away captain's reported home score
  final int? awayReportA; // away captain's reported away score
  final bool scoreDisputed;
  final DateTime createdAt;

  // Optional joined team fields
  final String? homeTeamName;
  final String? awayTeamName;
  final String? homeTeamLogo;
  final String? awayTeamLogo;
  final int? homeTeamRating;
  final int? awayTeamRating;

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
    this.homeOk = false,
    this.awayOk = false,
    this.homeReportH,
    this.homeReportA,
    this.awayReportH,
    this.awayReportA,
    this.scoreDisputed = false,
    required this.createdAt,
    this.homeTeamName,
    this.awayTeamName,
    this.homeTeamLogo,
    this.awayTeamLogo,
    this.homeTeamRating,
    this.awayTeamRating,
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
      homeOk: (json['home_ok'] as bool?) ?? false,
      awayOk: (json['away_ok'] as bool?) ?? false,
      homeReportH: json['home_report_h'] as int?,
      homeReportA: json['home_report_a'] as int?,
      awayReportH: json['away_report_h'] as int?,
      awayReportA: json['away_report_a'] as int?,
      scoreDisputed: (json['score_disputed'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      homeTeamName: home?['name'] as String?,
      awayTeamName: away?['name'] as String?,
      homeTeamLogo: home?['logo_url'] as String?,
      awayTeamLogo: away?['logo_url'] as String?,
      homeTeamRating: home?['rating'] as int?,
      awayTeamRating: away?['rating'] as int?,
    );
  }
}
