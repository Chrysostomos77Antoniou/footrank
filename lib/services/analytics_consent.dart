import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:footrank/services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Usage statistics are opt-in: nothing is collected until the user says yes
/// (on the terms screen or in Profile). Collection is also off by default in
/// the native config, so Firebase sends nothing before this runs.
class AnalyticsConsent {
  AnalyticsConsent._();

  static const _key = 'analytics_opt_in';

  static Future<bool> isOptedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Applies the saved choice at app start (after Firebase is up).
  static Future<void> apply() async => _setCollection(await isOptedIn());

  static Future<void> set(bool optIn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, optIn);
    } catch (_) {}
    await _setCollection(optIn);
  }

  static Future<void> _setCollection(bool on) async {
    if (on) {
      AppAnalytics.enable();
    } else {
      AppAnalytics.disable();
    }
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(on && !kDebugMode);
    } catch (_) {
      // Firebase not initialised (tests, failed init): nothing to switch.
    }
  }
}
