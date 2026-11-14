import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Google Maps Platform keys. They are restricted in Google Cloud to this
/// app's package / bundle id (and, on Android, its signing certificates) and to
/// the Maps SDK + Places API (New), so shipping them in the app is the
/// intended setup.
const String kMapsAndroidKey = 'AIzaSyCZBfXgXbfuaZw1-3bJA-CVoeYX4-uzZ4A';
const String kMapsIosKey = 'AIzaSyCReY1YstragSuHvHWVlCtL3hNd8SadwbI';
const String kAppPackageId = 'com.footballcy.footrank';

class MapsConfig {
  MapsConfig._();

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// The map and place search only exist on the phone apps.
  static bool get supported => !kIsWeb && (_isIos || _isAndroid);

  static String get apiKey => _isIos ? kMapsIosKey : kMapsAndroidKey;

  /// Headers for Places API (New) REST calls. A key restricted to an app only
  /// works when the call identifies that app, so these carry the bundle id
  /// (iOS) or package name + signing certificate SHA-1 (Android).
  static Future<Map<String, String>> placesHeaders({String? fieldMask}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      if (fieldMask != null) 'X-Goog-FieldMask': fieldMask,
    };
    if (_isIos) {
      headers['X-Ios-Bundle-Identifier'] = kAppPackageId;
    } else if (_isAndroid) {
      final info = await PackageInfo.fromPlatform();
      headers['X-Android-Package'] = kAppPackageId;
      headers['X-Android-Cert'] =
          info.buildSignature.replaceAll(':', '').toUpperCase();
    }
    return headers;
  }
}
