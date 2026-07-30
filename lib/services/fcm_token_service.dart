import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/services/notification_service.dart';
import 'package:footrank/services/supabase_service.dart';

/// Keeps the signed-in user's FCM device token in the `fcm_tokens` table so the
/// server (send-push Edge Function) can push to them. Synced on sign-in / session
/// restore / token refresh, and removed on sign-out so a shared device never
/// pushes one user's alerts to another.
class FcmTokenService {
  static String? _lastToken;

  /// Upsert this device's token for the current user.
  static Future<void> sync() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    try {
      final token = await NotificationService.currentToken();
      if (token == null) return;
      _lastToken = token;
      await SupabaseService.client.from('fcm_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Best-effort — never block the app on token sync.
    }
  }

  /// Remove this device's token (call before signing out, while still authed).
  static Future<void> remove() async {
    final user = SupabaseService.client.auth.currentUser;
    final token = _lastToken;
    if (user == null || token == null) return;
    try {
      await SupabaseService.client
          .from('fcm_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('token', token);
    } catch (_) {}
  }

  /// Start syncing the token on sign-in / session restore / refresh.
  static void init() {
    SupabaseService.client.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
          sync();
          break;
        default:
          break;
      }
    });
    NotificationService.onTokenRefresh.listen((_) => sync());
  }
}
