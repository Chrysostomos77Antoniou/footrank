import 'package:shared_preferences/shared_preferences.dart';

/// Intent the user expressed during onboarding for their first session after
/// signing up. Consumed once (and cleared) when the profile setup completes.
class OnboardingIntent {
  static const createTeam = 'create_team';
  static const freeAgent = 'free_agent';
}

/// Tracks whether the user has seen the first-run onboarding, plus the intent
/// they chose on the final slide so we can route their first session somewhere
/// purposeful instead of dropping them on an empty Home screen.
class OnboardingPrefs {
  static const _key = 'onboarding_seen_v1';
  static const _intentKey = 'onboarding_intent_v1';
  static bool seen = false;

  /// One of [OnboardingIntent] values, or null if none was chosen.
  static String? postSetupIntent;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    seen = prefs.getBool(_key) ?? false;
    postSetupIntent = prefs.getString(_intentKey);
  }

  static Future<void> markSeen() async {
    seen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Records (or clears, when [intent] is null) the user's first-session intent.
  static Future<void> setPostSetupIntent(String? intent) async {
    postSetupIntent = intent;
    final prefs = await SharedPreferences.getInstance();
    if (intent == null) {
      await prefs.remove(_intentKey);
    } else {
      await prefs.setString(_intentKey, intent);
    }
  }
}
