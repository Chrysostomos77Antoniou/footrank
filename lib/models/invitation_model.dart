class InvitationModel {
  final String id;
  final String teamId;
  final String userId;
  final String status; // 'pending' | 'accepted' | 'declined'
  final DateTime createdAt;

  // Joined team fields (for the invitee's view)
  final String teamName;
  final String? teamCity;

  const InvitationModel({
    required this.id,
    required this.teamId,
    required this.userId,
    required this.status,
    required this.createdAt,
    required this.teamName,
    this.teamCity,
  });

  /// Expects a row from team_invitations with a nested `teams` object.
  factory InvitationModel.fromJson(Map<String, dynamic> json) {
    final team = (json['teams'] as Map<String, dynamic>?) ?? const {};
    return InvitationModel(
      id: json['id'] as String,
      teamId: json['team_id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      teamName: (team['name'] as String?) ?? 'Unknown team',
      teamCity: team['city'] as String?,
    );
  }
}
