import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level background handler (required by FCM to be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep minimal; heavy work should be deferred.
  debugPrint('BG message: ${message.messageId}');
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

  /// Call after Firebase.initializeApp(). Requests permission, wires handlers,
  /// and returns the device FCM token (null if unavailable / denied).
  static Future<String?> initialize() async {
    // iOS / Android 13+ runtime permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('Notification permission: ${settings.authorizationStatus}');

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FG message: ${message.notification?.title}');
    });

    // Tapped notification that opened the app
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Opened from notification: ${message.data}');
    });

    final token = await _messaging.getToken();
    debugPrint('FCM token: $token');
    return token;
  }

  /// Listen for token refreshes (e.g. to persist server-side).
  static Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// The current device FCM token, or null if unavailable.
  static Future<String?> currentToken() async {
    try {
      return await _messaging.getToken();
    } catch (_) {
      return null;
    }
  }
}
