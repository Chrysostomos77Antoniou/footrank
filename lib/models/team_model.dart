class TeamModel {
  final String id;
  final String name;
  final String? city;
  final String? logoUrl;
  final String captainId;
  final int rating;
  final String? inviteCode;
  final int wins;
  final int losses;
  final int draws;
  final DateTime createdAt;

  const TeamModel({
    required this.id,
    required this.name,
    this.city,
    this.logoUrl,
    required this.captainId,
    this.rating = 1500,
    this.inviteCode,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    required this.createdAt,
  });

  /// Short W–L (–D) record, e.g. "5W · 2L" or "5W · 2L · 1D".
  String get record {
    final base = '${wins}W · ${losses}L';
    return draws > 0 ? '$base · ${draws}D' : base;
  }

  int get played => wins + losses + draws;

  factory TeamModel.fromJson(Map<String, dynamic> json) => TeamModel(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String?,
        logoUrl: json['logo_url'] as String?,
        captainId: json['captain_id'] as String,
        rating: (json['rating'] as int?) ?? 1500,
        inviteCode: json['invite_code'] as String?,
        wins: (json['wins'] as int?) ?? 0,
        losses: (json['losses'] as int?) ?? 0,
        draws: (json['draws'] as int?) ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
