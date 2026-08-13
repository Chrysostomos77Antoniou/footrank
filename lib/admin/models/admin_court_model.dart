/// Full court record for the admin panel -- unlike the public-facing
/// [CourtModel] (which deliberately hides phone/hours from regular users),
/// this exposes every column since the admin is the one maintaining them.
class AdminCourtModel {
  final String id;
  final String name;
  final String city;
  final String? address;
  final String? phone;
  final String? website;
  final String? hours;
  final String? imageUrl;
  final bool active;
  final int? sortOrder;

  const AdminCourtModel({
    required this.id,
    required this.name,
    required this.city,
    this.address,
    this.phone,
    this.website,
    this.hours,
    this.imageUrl,
    required this.active,
    this.sortOrder,
  });

  factory AdminCourtModel.fromJson(Map<String, dynamic> json) =>
      AdminCourtModel(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        website: json['website'] as String?,
        hours: json['hours'] as String?,
        imageUrl: json['image_url'] as String?,
        active: json['active'] as bool? ?? true,
        sortOrder: json['sort_order'] as int?,
      );

  AdminCourtModel copyWith({
    String? name,
    String? city,
    String? address,
    String? phone,
    String? website,
    String? hours,
    String? imageUrl,
    bool? active,
    int? sortOrder,
  }) => AdminCourtModel(
    id: id,
    name: name ?? this.name,
    city: city ?? this.city,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    website: website ?? this.website,
    hours: hours ?? this.hours,
    imageUrl: imageUrl ?? this.imageUrl,
    active: active ?? this.active,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}
