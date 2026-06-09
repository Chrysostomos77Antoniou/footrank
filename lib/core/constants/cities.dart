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
