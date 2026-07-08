class MatchRequestModel {
  final String id;
  final String teamId;
  final String captainId;
  final String city;
  final DateTime scheduledAt;
  final String matchType; // 'casual' | 'ranked'
  final String format; // '5v5'
  final String status; // searching | pending | confirmed | completed
  final DateTime createdAt;

  // Optional joined team fields
  final String? teamName;
  final int? teamRating;
  final String? teamLogo;

  // Set by MatchRepository.findOpponents — how well this opponent's ranked
  // court picks overlap with yours (higher = better; null = not computed).
  final int? courtCompatibilityScore;

  // Set by MatchRepository.findAllOpponents — which of YOUR OWN open
  // requests this opponent matched against, so acceptMatchRequest() knows
  // whose court picks to resolve against.
  final String? matchedFromRequestId;

  const MatchRequestModel({
    required this.id,
    required this.teamId,
    required this.captainId,
    required this.city,
    required this.scheduledAt,
    required this.matchType,
    required this.format,
    required this.status,
    required this.createdAt,
    this.teamName,
    this.teamRating,
    this.teamLogo,
    this.courtCompatibilityScore,
    this.matchedFromRequestId,
  });

  bool get isRanked => matchType == 'ranked';

  MatchRequestModel copyWith({
    int? courtCompatibilityScore,
    String? matchedFromRequestId,
  }) =>
      MatchRequestModel(
        id: id,
        teamId: teamId,
        captainId: captainId,
        city: city,
        scheduledAt: scheduledAt,
        matchType: matchType,
        format: format,
        status: status,
        createdAt: createdAt,
        teamName: teamName,
        teamRating: teamRating,
        teamLogo: teamLogo,
        courtCompatibilityScore:
            courtCompatibilityScore ?? this.courtCompatibilityScore,
        matchedFromRequestId: matchedFromRequestId ?? this.matchedFromRequestId,
      );

  factory MatchRequestModel.fromJson(Map<String, dynamic> json) {
    final team = json['teams'] as Map<String, dynamic>?;
    return MatchRequestModel(
      id: json['id'] as String,
      teamId: json['team_id'] as String,
      captainId: json['captain_id'] as String,
      city: json['city'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      matchType: json['match_type'] as String,
      format: json['format'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      teamName: team?['name'] as String?,
      teamRating: team?['rating'] as int?,
      teamLogo: team?['logo_url'] as String?,
    );
  }
}
