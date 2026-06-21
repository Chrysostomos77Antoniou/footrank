import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has seen the first-run onboarding.
class OnboardingPrefs {
  static const _key = 'onboarding_seen_v1';
  static bool seen = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    seen = prefs.getBool(_key) ?? false;
  }

  static Future<void> markSeen() async {
    seen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
