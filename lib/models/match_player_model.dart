class MatchPlayerModel {
  final String matchId;
  final String userId;
  final String teamId;
  final bool? attended; // null = not yet marked

  const MatchPlayerModel({
    required this.matchId,
    required this.userId,
    required this.teamId,
    this.attended,
  });

  factory MatchPlayerModel.fromJson(Map<String, dynamic> json) =>
      MatchPlayerModel(
        matchId: json['match_id'] as String,
        userId: json['user_id'] as String,
        teamId: json['team_id'] as String,
        attended: json['attended'] as bool?,
      );
}
