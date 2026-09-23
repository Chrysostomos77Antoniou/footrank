import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:footrank/app.dart';
import 'package:footrank/auth/data/auth_flow.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/firebase_options.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
import 'package:footrank/payment/data/payment_repository.dart';
import 'package:footrank/services/fcm_token_service.dart';
import 'package:footrank/services/notification_service.dart';
import 'package:footrank/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use Android's system Photo Picker (gallery grid) where available.
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) {
    picker.useAndroidPhotoPicker = true;
  }

  await themeController.load();
  await OnboardingPrefs.load();
  await SupabaseService.initialize();
  // Stripe SDK setup for the match fee. No-ops when STRIPE_PUBLISHABLE_KEY
  // isn't defined, so debug builds and tests need no Stripe account. Must
  // complete before any PaymentSheet is presented, hence awaited here rather
  // than lazily on first use.
  await PaymentRepository.initialize();
  // Watch for the password-recovery deep link so we can route to the reset page.
  initPasswordRecoveryListener();

  // Must be registered right after Supabase itself initializes -- it fires
  // an `initialSession` event synchronously as part of setup, and that's a
  // broadcast stream with no replay: subscribing any later (e.g. after the
  // Firebase block below, which can take several seconds) silently misses
  // it forever for anyone whose session is being restored rather than
  // freshly signed in, so their FCM token would never get synced at all.
  // This half is safe to call before Firebase exists -- see its doc comment.
  FcmTokenService.initAuthListener();

  // Firebase + push notifications (Task 11.1). Guarded so a failure here
  // never blocks the app from launching.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Crash reporting: route Flutter + platform errors to Crashlytics.
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    // Permission prompt, foreground presentation and every FCM/local
    // notification handler -- all still in place before the first frame.
    await NotificationService.initialize();
    // The token half (iOS's APNs wait, getToken(), the fcm_tokens upsert) is
    // network-bound and nothing on screen reads it, so it runs alongside the
    // first frames instead of in front of them -- same steps, same order.
    // Sign-out waits for it (see FcmTokenService.remove).
    FcmTokenService.trackLaunchSync(_syncPushToken());
  } catch (e, st) {
    await _reportPushInitFailure(e, st);
  }

  runApp(const FootRankApp());
}

/// Launch-time token registration; see the call site in [main].
Future<void> _syncPushToken() async {
  try {
    await NotificationService.fetchInitialToken();
    // This half touches FirebaseMessaging.instance immediately and must not
    // run until Firebase is actually ready (see its doc comment).
    FcmTokenService.initTokenRefreshListener();
    // Belt-and-braces: don't rely solely on the auth listener above having
    // caught the right event -- explicitly sync once the token is actually
    // obtainable (it isn't until Firebase/APNs init above has completed).
    await FcmTokenService.sync();
  } catch (e, st) {
    await _reportPushInitFailure(e, st);
  }
}

Future<void> _reportPushInitFailure(Object e, StackTrace st) async {
  debugPrint('Firebase/notifications init failed: $e');
  // Best-effort: only reports if Firebase.initializeApp() itself succeeded
  // (Crashlytics needs that to be ready). Without this, push-registration
  // failures were invisible in production -- just a local debugPrint.
  try {
    await FirebaseCrashlytics.instance.recordError(
      e,
      st,
      fatal: false,
      reason: 'push notification init failed',
    );
  } catch (_) {}
}
