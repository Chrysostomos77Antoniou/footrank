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
