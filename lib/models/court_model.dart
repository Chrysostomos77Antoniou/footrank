/// A bookable court, scoped to a city. Deliberately excludes phone — captains
/// pick by name/address/photo only; the owner (who makes the actual booking
/// call) sees the phone number separately via the Mission Control alert.
class CourtModel {
  final String id;
  final String name;
  final String city;
  final String? address;
  final String? imageUrl;

  const CourtModel({
    required this.id,
    required this.name,
    required this.city,
    this.address,
    this.imageUrl,
  });

  factory CourtModel.fromJson(Map<String, dynamic> json) => CourtModel(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String,
        address: json['address'] as String?,
        imageUrl: json['image_url'] as String?,
      );
}
