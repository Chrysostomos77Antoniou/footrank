class TeamMemberModel {
  final String teamId;
  final String userId;
  final String role; // 'captain' | 'vice_captain' | 'player'
  final DateTime joinedAt;

  // Joined user fields (from public.users)
  final String name;
  final String username;
  final String? position;
  final int elo;
  final int reliability;
  final int behaviorPositive;
  final int behaviorNegative;

  const TeamMemberModel({
    required this.teamId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.name,
    required this.username,
    this.position,
    required this.elo,
    this.reliability = 100,
    this.behaviorPositive = 0,
    this.behaviorNegative = 0,
  });

  bool get isCaptain => role == 'captain';
  bool get isViceCaptain => role == 'vice_captain';

  /// Behavior rating label based on positive/negative ratio.
  String get behaviorLabel {
    final total = behaviorPositive + behaviorNegative;
    if (total == 0) return 'Unrated';
    final ratio = behaviorPositive / total;
    if (ratio >= 0.9) return 'Excellent';
    if (ratio >= 0.7) return 'Good';
    if (ratio >= 0.5) return 'Average';
    return 'Poor';
  }

  String get roleLabel {
    switch (role) {
      case 'captain':
        return 'Captain';
      case 'vice_captain':
        return 'Vice Captain';
      default:
        return 'Player';
    }
  }

  /// Expects a row from team_members with a nested `users` object.
  factory TeamMemberModel.fromJson(Map<String, dynamic> json) {
    final user = (json['users'] as Map<String, dynamic>?) ?? const {};
    return TeamMemberModel(
      teamId: json['team_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      name: (user['name'] as String?) ?? 'Unknown',
      username: (user['username'] as String?) ?? '',
      position: user['position'] as String?,
      elo: (user['elo'] as int?) ?? 1500,
      reliability: (user['reliability'] as int?) ?? 100,
      behaviorPositive: (user['behavior_positive'] as int?) ?? 0,
      behaviorNegative: (user['behavior_negative'] as int?) ?? 0,
    );
  }
}
