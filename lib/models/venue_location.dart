/// Where a venue is on the map. Stored next to the typed venue name on
/// requests, proposals and matches.
///
/// [placeId] is a Google place id (stays valid for directions); [lat]/[lng] are
/// kept for the small map preview. Google only allows its coordinates to be
/// kept for a limited time, so the server clears them from Google-sourced rows
/// after 30 days -- directions then fall back to the place id. Pins dropped by
/// hand ([source] == 'manual') are the captain's own data and are kept.
class VenueLocation {
  final String? placeId;
  final double? lat;
  final double? lng;

  /// 'google' (picked from search) or 'manual' (pin dropped on the map).
  final String source;

  const VenueLocation({
    this.placeId,
    this.lat,
    this.lng,
    this.source = 'google',
  });

  bool get hasCoords => lat != null && lng != null;
  bool get isManual => source == 'manual';

  /// Column values for the match_requests insert.
  Map<String, dynamic> toColumns() => {
        'venue_place_id': placeId,
        'venue_lat': lat,
        'venue_lng': lng,
        'venue_source': source,
      };

  /// Null when the row carries no usable location (older requests).
  static VenueLocation? fromJson(Map<String, dynamic> json) {
    final placeId = json['venue_place_id'] as String?;
    final lat = (json['venue_lat'] as num?)?.toDouble();
    final lng = (json['venue_lng'] as num?)?.toDouble();
    if (placeId == null && (lat == null || lng == null)) return null;
    return VenueLocation(
      placeId: placeId,
      lat: lat,
      lng: lng,
      source: (json['venue_source'] as String?) ?? 'google',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VenueLocation &&
      other.placeId == placeId &&
      other.lat == lat &&
      other.lng == lng &&
      other.source == source;

  @override
  int get hashCode => Object.hash(placeId, lat, lng, source);
}
