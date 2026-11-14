/// The fixed set of cities FootRank operates in. Used for profiles, teams,
/// and match requests so matchmaking can reliably match on city.
const List<String> kCities = [
  'Nicosia',
  'Limassol',
  'Famagusta',
  'Larnaca',
  'Paphos',
];

/// Maps any stored city string to the canonical list entry (case-insensitive),
/// or null if it doesn't match — so dropdowns never crash on a stale value.
String? canonicalCity(String? value) {
  if (value == null) return null;
  final v = value.trim().toLowerCase();
  for (final c in kCities) {
    if (c.toLowerCase() == v) return c;
  }
  return null;
}

/// Approximate centre (latitude, longitude) of each city, used to open the
/// venue map on the right town and to bias place search.
const Map<String, List<double>> kCityCenters = {
  'Nicosia': [35.1856, 33.3823],
  'Limassol': [34.7071, 33.0226],
  'Famagusta': [35.0420, 33.9800],
  'Larnaca': [34.9229, 33.6233],
  'Paphos': [34.7754, 32.4245],
};
