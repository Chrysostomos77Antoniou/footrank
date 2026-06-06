class TeamModel {
  final String id;
  final String name;
  final String? city;
  final String? logoUrl;
  final String captainId;
  final int rating;
  final String? inviteCode;
  final DateTime createdAt;

  const TeamModel({
    required this.id,
    required this.name,
    this.city,
    this.logoUrl,
    required this.captainId,
    this.rating = 1500,
    this.inviteCode,
    required this.createdAt,
  });

  factory TeamModel.fromJson(Map<String, dynamic> json) => TeamModel(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String?,
        logoUrl: json['logo_url'] as String?,
        captainId: json['captain_id'] as String,
        rating: (json['rating'] as int?) ?? 1500,
        inviteCode: json['invite_code'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
