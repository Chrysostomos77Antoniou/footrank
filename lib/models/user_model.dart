class UserModel {
  final String id;
  final String name;
  final String username;
  final String? city;
  final String? position;
  final int elo;
  final int reliability;
  final int behaviorPositive;
  final int behaviorNegative;
  final int matchesPlayed;
  final String? avatarUrl;
  final int disputeCount;
  final bool flagged;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.username,
    this.city,
    this.position,
    this.elo = 1500,
    this.reliability = 100,
    this.behaviorPositive = 0,
    this.behaviorNegative = 0,
    this.matchesPlayed = 0,
    this.avatarUrl,
    this.disputeCount = 0,
    this.flagged = false,
    required this.createdAt,
  });

  /// Human-readable behavior rating based on positive/negative ratio.
  String get behaviorLabel {
    final total = behaviorPositive + behaviorNegative;
    if (total == 0) return 'Unrated';
    final ratio = behaviorPositive / total;
    if (ratio >= 0.9) return 'Excellent';
    if (ratio >= 0.7) return 'Good';
    if (ratio >= 0.5) return 'Average';
    return 'Poor';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        name: json['name'] as String,
        username: json['username'] as String,
        city: json['city'] as String?,
        position: json['position'] as String?,
        elo: (json['elo'] as int?) ?? 1500,
        reliability: (json['reliability'] as int?) ?? 100,
        behaviorPositive: (json['behavior_positive'] as int?) ?? 0,
        behaviorNegative: (json['behavior_negative'] as int?) ?? 0,
        matchesPlayed: (json['matches_played'] as int?) ?? 0,
        avatarUrl: json['avatar_url'] as String?,
        disputeCount: (json['dispute_count'] as int?) ?? 0,
        flagged: (json['flagged'] as bool?) ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'id': id,
        'name': name,
        'username': username,
        'city': city,
        'position': position,
      };
}
