import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:footrank/core/config/maps_config.dart';
import 'package:http/http.dart' as http;

/// One row of the place search list.
class PlaceSuggestion {
  final String placeId;

  /// The place's own name (e.g. "Arena Futsal Center").
  final String name;

  /// Street / area line shown under the name.
  final String secondary;

  const PlaceSuggestion({
    required this.placeId,
    required this.name,
    required this.secondary,
  });
}

class PlaceCoords {
  final double lat;
  final double lng;
  const PlaceCoords(this.lat, this.lng);
}

class PlacesException implements Exception {
  final String message;
  const PlacesException(this.message);
  @override
  String toString() => message;
}

/// Place search over the Places API (New), billed so that it stays in the free
/// tiers: one search "session" (autocomplete as the user types, ended by a
/// single details call for the chosen place) and only the cheapest field
/// (location). The place's name comes from the autocomplete result itself.
class PlacesService {
  final http.Client _client;
  String _session = _newSessionToken();

  PlacesService({http.Client? client}) : _client = client ?? http.Client();

  static const _host = 'places.googleapis.com';
  static const _timeout = Duration(seconds: 8);

  static String _newSessionToken() {
    final r = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    final variant = (8 + r.nextInt(4)).toRadixString(16);
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }

  /// Suggestions for [input], biased to the circle around ([biasLat],[biasLng]).
  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    required double biasLat,
    required double biasLng,
  }) async {
    final text = input.trim();
    if (text.length < 2) return const [];
    final headers = await MapsConfig.placesHeaders();
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.https(_host, '/v1/places:autocomplete'),
            headers: headers,
            body: jsonEncode({
              'input': text,
              'sessionToken': _session,
              'includedRegionCodes': ['cy'],
              'locationBias': {
                'circle': {
                  'center': {'latitude': biasLat, 'longitude': biasLng},
                  'radius': 30000.0,
                },
              },
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const PlacesException('Search timed out. Check your connection.');
    } catch (_) {
      throw const PlacesException('Search is not available right now.');
    }
    if (res.statusCode != 200) {
      throw const PlacesException('Search is not available right now.');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final out = <PlaceSuggestion>[];
    for (final s in (body['suggestions'] as List? ?? const [])) {
      final p = (s as Map<String, dynamic>)['placePrediction']
          as Map<String, dynamic>?;
      if (p == null) continue;
      final id = p['placeId'] as String?;
      final fmt = p['structuredFormat'] as Map<String, dynamic>?;
      final main = (fmt?['mainText'] as Map<String, dynamic>?)?['text']
              as String? ??
          (p['text'] as Map<String, dynamic>?)?['text'] as String?;
      final sec = (fmt?['secondaryText'] as Map<String, dynamic>?)?['text']
              as String? ??
          '';
      if (id == null || main == null) continue;
      out.add(PlaceSuggestion(placeId: id, name: main, secondary: sec));
    }
    return out;
  }

  /// The coordinates of a chosen suggestion. Closing the search session here
  /// keeps the autocomplete calls free.
  Future<PlaceCoords> coordsOf(String placeId) async {
    final headers = await MapsConfig.placesHeaders(fieldMask: 'id,location');
    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.https(_host, '/v1/places/$placeId',
                {'sessionToken': _session}),
            headers: headers,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const PlacesException('Search timed out. Check your connection.');
    } catch (_) {
      throw const PlacesException('Could not load that place.');
    }
    // A new search session starts after every pick.
    _session = _newSessionToken();
    if (res.statusCode != 200) {
      throw const PlacesException('Could not load that place.');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final loc = body['location'] as Map<String, dynamic>?;
    final lat = (loc?['latitude'] as num?)?.toDouble();
    final lng = (loc?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      throw const PlacesException('Could not load that place.');
    }
    return PlaceCoords(lat, lng);
  }

  void dispose() => _client.close();
}
