/// A team member's offer to play a specific open [MatchRequestModel] --
/// proposing is open to any team member, not just captains. The request's
/// own captain accepts or rejects each proposal; accepting one auto-cancels
/// every other pending proposal on the same request, plus any other pending
/// proposal either now-committed team has on a request scheduled the same
/// calendar day.
class MatchProposalModel {
  final String id;
  final String requestId;
  final String proposingTeamId;
  final String proposingUserId;
  final String status; // pending | accepted | rejected | cancelled
  final DateTime createdAt;
  final DateTime? resolvedAt;

  // Optional joined proposing-team fields (used when listing INCOMING
  // proposals on a request you own -- who's proposing).
  final String? teamName;
  final int? teamRating;
  final String? teamLogo;

  // Optional joined target-request fields (used when listing OUTGOING
  // proposals your team sent -- what you proposed for, and against whom).
  final String? requestCity;
  final DateTime? requestScheduledAt;
  final String? requestMatchType;
  final String? requestFormat;
  final String? targetTeamName;
  final int? targetTeamRating;
  final String? targetTeamLogo;

  const MatchProposalModel({
    required this.id,
    required this.requestId,
    required this.proposingTeamId,
    required this.proposingUserId,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.teamName,
    this.teamRating,
    this.teamLogo,
    this.requestCity,
    this.requestScheduledAt,
    this.requestMatchType,
    this.requestFormat,
    this.targetTeamName,
    this.targetTeamRating,
    this.targetTeamLogo,
  });

  bool get isPending => status == 'pending';

  factory MatchProposalModel.fromJson(Map<String, dynamic> json) {
    final team = json['teams'] as Map<String, dynamic>?;
    final request = json['match_requests'] as Map<String, dynamic>?;
    final targetTeam = request?['teams'] as Map<String, dynamic>?;
    return MatchProposalModel(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      proposingTeamId: json['proposing_team_id'] as String,
      proposingUserId: json['proposing_user_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      teamName: team?['name'] as String?,
      teamRating: team?['rating'] as int?,
      teamLogo: team?['logo_url'] as String?,
      requestCity: request?['city'] as String?,
      requestScheduledAt: request?['scheduled_at'] != null
          ? DateTime.parse(request!['scheduled_at'] as String)
          : null,
      requestMatchType: request?['match_type'] as String?,
      requestFormat: request?['format'] as String?,
      targetTeamName: targetTeam?['name'] as String?,
      targetTeamRating: targetTeam?['rating'] as int?,
      targetTeamLogo: targetTeam?['logo_url'] as String?,
    );
  }
}
