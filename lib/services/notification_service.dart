import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:footrank/services/notification_router.dart';
import 'package:footrank/services/supabase_service.dart';

/// Top-level background handler (required by FCM to be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep minimal; heavy work should be deferred. The OS already shows the
  // system notification for background/killed messages on its own (that's
  // native FCM behaviour), so nothing more is needed here.
  debugPrint('BG message: ${message.messageId}');
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  // Android only shows a system banner for FCM messages automatically when
  // the app is backgrounded/killed -- while the app is in the foreground,
  // onMessage fires but nothing is displayed unless we show a local
  // notification ourselves. Without this, every push while the app is open
  // was landing silently in the in-app inbox only, invisible until the user
  // happened to check it -- unlike Instagram, which still banners you for a
  // new message even while you're using the app.
  static const _androidChannel = AndroidNotificationChannel(
    'footrank_high_importance',
    'FootRank notifications',
    description: 'Match requests, proposals, confirmations and reminders.',
    importance: Importance.max,
  );

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
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      await logTokenIssue(
        'Permission not granted: ${settings.authorizationStatus}',
      );
    }

    // iOS already banners foreground messages natively once this is set --
    // no local-notifications plugin needed on that platform.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _initLocalNotifications();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Foreground messages: Android needs an explicit local notification to
    // actually show anything -- iOS is already covered by the presentation
    // options set above, so showing it again there would double-banner.
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FG message: ${message.notification?.title}');
      if (Platform.isAndroid) _showForegroundBanner(message);
    });

    // Tapped a notification that opened the app from background -- sync and
    // deep-link straight to whatever it was about.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      handleNotificationTap(
        type: message.data['type'] as String?,
        referenceId: message.data['reference_id'] as String?,
      );
    });

    final token = await currentToken();
    debugPrint('FCM token: $token');
    return token;
  }

  /// The push that launched the app from a fully terminated state, if any.
  /// Callers must defer acting on this until the router/navigator exists.
  static Future<RemoteMessage?> getInitialMessage() =>
      _messaging.getInitialMessage();

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      initSettings,
      // Tapped the local banner we show for Android foreground messages --
      // Firebase has no visibility into this one (it's not the OS's own FCM
      // notification), so it's handled entirely through this callback.
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        final data = jsonDecode(payload) as Map<String, dynamic>;
        handleNotificationTap(
          type: data['type'] as String?,
          referenceId: data['reference_id'] as String?,
        );
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  static void _showForegroundBanner(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Listen for token refreshes (e.g. to persist server-side).
  static Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// The current device FCM token, or null if unavailable.
  static Future<String?> currentToken() async {
    try {
      if (Platform.isIOS) {
        // On iOS, FCM can't mint a token until APNs registration completes --
        // calling getToken() before that finishes throws or returns null, and
        // there's no push-side symptom for this since it fails before a
        // token ever reaches the server (unlike a bad APNs cert, which fails
        // *after* the token exists, at send time).
        var apnsToken = await _messaging.getAPNSToken();
        var attempts = 0;
        while (apnsToken == null && attempts < 10) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await _messaging.getAPNSToken();
          attempts++;
        }
        if (apnsToken == null) {
          await logTokenIssue('APNs token not available after ${attempts}s wait');
          return null;
        }
      }
      final token = await _messaging.getToken();
      if (token == null) {
        await logTokenIssue('getToken() returned null');
      }
      return token;
    } catch (e) {
      await logTokenIssue('getToken() threw: $e');
      return null;
    }
  }

  /// Best-effort diagnostic trail for why a device never got/synced a push
  /// token -- there's no Xcode console access for TestFlight builds, so this
  /// is queried directly from the database instead. Public: also called from
  /// FcmTokenService when the sync (not just the getToken() call) fails.
  static Future<void> logTokenIssue(String message) async {
    debugPrint('FCM token issue: $message');
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;
      await SupabaseService.client.from('push_debug_log').insert({
        'user_id': user.id,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'message': message,
      });
    } catch (_) {}
  }
}
