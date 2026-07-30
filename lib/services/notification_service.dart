import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

    // Tapped notification that opened the app
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Opened from notification: ${message.data}');
    });

    final token = await _messaging.getToken();
    debugPrint('FCM token: $token');
    return token;
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);
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
    );
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
