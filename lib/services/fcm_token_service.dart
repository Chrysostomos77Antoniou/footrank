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
    } catch (e) {
      // Best-effort — never block the app on token sync, but a token that
      // was obtained and then failed to save is just as invisible as one
      // that was never obtained, so it still needs to be logged.
      await NotificationService.logTokenIssue('fcm_tokens upsert failed: $e');
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

  /// Start syncing on sign-in / session restore. Must be called immediately
  /// after Supabase itself initializes -- it fires an `initialSession` event
  /// synchronously as part of setup, and that's a broadcast stream with no
  /// replay, so subscribing any later silently misses it forever for anyone
  /// whose session is being restored rather than freshly signed in.
  ///
  /// Safe to call before Firebase.initializeApp(): this only touches
  /// Supabase's own auth stream at subscribe time. The one thing that does
  /// touch Firebase (NotificationService.currentToken(), inside sync()) only
  /// runs later, inside the event callback, and already catches its own
  /// errors -- so an event firing before Firebase is ready just logs and
  /// moves on instead of crashing.
  static void initAuthListener() {
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
  }

  /// Start re-syncing whenever FCM mints a new token. Unlike the listener
  /// above, this evaluates NotificationService.onTokenRefresh (and so
  /// FirebaseMessaging.instance) the moment it's called, with nothing to
  /// catch a failure -- calling this before Firebase.initializeApp() has
  /// completed throws immediately and crashes app startup. Only call it
  /// after Firebase/NotificationService have finished initializing.
  static void initTokenRefreshListener() {
    NotificationService.onTokenRefresh.listen((_) => sync());
  }
}
