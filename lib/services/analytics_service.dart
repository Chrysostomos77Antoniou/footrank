import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Product analytics: a handful of events that answer "do people come back,
/// and do teams actually play?" so pricing can be decided from data.
///
/// Safe by construction: it does nothing until [enable] is called (main() does
/// that once Firebase is up, and never in debug builds), it never throws, and
/// it never waits -- a failed or slow analytics call can not affect the app.
/// No names, emails or free text are ever sent; only counts and categories.
///
/// Events (Firebase also gives retention, daily/weekly actives and sessions
/// for free):
///   sign_up, team_created, match_request_created, match_proposed,
///   proposal_accepted, score_submitted, fee_paid.
class AppAnalytics {
  AppAnalytics._();

  static bool _enabled = false;

  /// Turn event logging on. Debug builds stay off so test taps do not pollute
  /// the numbers.
  static void enable() => _enabled = !kDebugMode;

  /// Stop logging (the user withdrew consent for usage statistics).
  static void disable() => _enabled = false;

  static void log(String name, [Map<String, Object>? parameters]) {
    if (!_enabled) return;
    try {
      unawaited(
        FirebaseAnalytics.instance
            .logEvent(name: name, parameters: parameters)
            .catchError((Object _) {}),
      );
    } catch (_) {
      // Analytics must never break a user action.
    }
  }
}
