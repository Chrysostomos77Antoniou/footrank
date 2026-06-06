class JoinRequestModel {
  final String id;
  final String teamId;
  final String userId;
  final String status; // 'pending' | 'approved' | 'rejected'
  final DateTime createdAt;

  // Joined requester fields
  final String name;
  final String username;
  final String? position;
  final int elo;

  const JoinRequestModel({
    required this.id,
    required this.teamId,
    required this.userId,
    required this.status,
    required this.createdAt,
    required this.name,
    required this.username,
    this.position,
    required this.elo,
  });

  /// Expects a row from team_join_requests with a nested `users` object.
  factory JoinRequestModel.fromJson(Map<String, dynamic> json) {
    final user = (json['users'] as Map<String, dynamic>?) ?? const {};
    return JoinRequestModel(
      id: json['id'] as String,
      teamId: json['team_id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      name: (user['name'] as String?) ?? 'Unknown',
      username: (user['username'] as String?) ?? '',
      position: user['position'] as String?,
      elo: (user['elo'] as int?) ?? 1500,
    );
  }
}
