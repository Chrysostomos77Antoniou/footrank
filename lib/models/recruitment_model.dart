import 'package:footrank/models/team_model.dart';

/// A captain's "we need N players" post (`team_recruitments`), with the
/// posting team embedded for the Recruit list.
class RecruitmentModel {
  final String id;
  final String teamId;
  final int spots;
  final int accepted;
  final String? position;
  final String? note;
  final DateTime expiresAt;
  final TeamModel? team;

  const RecruitmentModel({
    required this.id,
    required this.teamId,
    required this.spots,
    required this.accepted,
    this.position,
    this.note,
    required this.expiresAt,
    this.team,
  });

  int get spotsLeft => spots - accepted;

  factory RecruitmentModel.fromJson(Map<String, dynamic> json) {
    final team = json['teams'];
    return RecruitmentModel(
      id: json['id'] as String,
      teamId: json['team_id'] as String,
      spots: json['spots'] as int,
      accepted: (json['accepted'] as int?) ?? 0,
      position: json['position'] as String?,
      note: json['note'] as String?,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      team: team is Map<String, dynamic> ? TeamModel.fromJson(team) : null,
    );
  }
}
