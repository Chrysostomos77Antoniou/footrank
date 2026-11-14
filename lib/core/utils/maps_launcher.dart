import 'package:footrank/models/venue_location.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Google Maps (app if installed, else browser) with a search for
/// [name] + [address] + [city] — used everywhere a court's location needs to
/// be shown, so every screen resolves the same way.
Future<void> openInMaps({
  required String name,
  String? address,
  required String city,
}) async {
  final query = [name, if (address != null) address, city].join(', ');
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// One tap to the venue on the map. Uses the exact place when the captain
/// picked it from the map search (place id), the dropped pin for a hand-placed
/// one, and falls back to a name search for older matches without a location.
Future<void> openVenueInMaps({
  required String name,
  required String city,
  VenueLocation? location,
}) async {
  final loc = location;
  if (loc == null) {
    return openInMaps(name: name, city: city);
  }
  final text = loc.hasCoords && (loc.isManual || loc.placeId == null)
      ? '${loc.lat},${loc.lng}'
      : [name, city].join(', ');
  final params = <String, String>{'api': '1', 'query': text};
  if (loc.placeId != null && !loc.isManual) {
    params['query_place_id'] = loc.placeId!;
  }
  await launchUrl(
    Uri.https('www.google.com', '/maps/search/', params),
    mode: LaunchMode.externalApplication,
  );
}
