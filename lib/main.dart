import 'dart:async';
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

  // These four are independent of each other, so run them concurrently
  // instead of one after another. All four are needed before the first
  // frame -- theme + onboarding state feed MaterialApp/the router directly,
  // and the router's redirect reads Supabase's auth state immediately -- so
  // this batch still fully completes before runApp(), it just takes as long
  // as the slowest one instead of the sum of all four.
  await Future.wait([
    themeController.load(),
    OnboardingPrefs.load(),
    SupabaseService.initialize(),
    // Stripe SDK setup for the match fee. No-ops when STRIPE_PUBLISHABLE_KEY
    // isn't defined, so debug builds and tests need no Stripe account. Must
    // complete before any PaymentSheet is presented, which is nowhere near
    // this early, but it's cheap and safe to ride along in this same batch.
    PaymentRepository.initialize(),
  ]);

  // Must be registered right after Supabase itself initializes -- it fires
  // an `initialSession` event synchronously as part of setup, and that's a
  // broadcast stream with no replay: subscribing any later silently misses
  // it forever for anyone whose session is being restored rather than
  // freshly signed in, so their FCM token would never get synced at all.
  // This half is safe to call before Firebase exists -- see its doc comment.
  FcmTokenService.initAuthListener();

  // Watch for the password-recovery deep link so we can route to the reset page.
  initPasswordRecoveryListener();

  // Only the bare app-initialization call needs to finish before runApp():
  // app.dart's very first post-frame callback calls
  // NotificationService.getInitialMessage(), which needs a Firebase app to
  // exist (see its doc comment). Everything else Firebase-related --
  // requesting notification permission, wiring FCM listeners, and syncing
  // the device token to the server over the network -- does NOT need to
  // finish before the user sees anything, so it's deferred until after
  // runApp() below instead of sitting in front of the splash video and the
  // rest of the UI like it used to. That deferred chunk alone could take a
  // second or more (a native permission prompt plus a network round trip),
  // and none of it was ever visible to the user anyway.
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
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  runApp(const FootRankApp());

  // Fire-and-forget: see the comment above for why this is safe to run
  // after the app is already on screen.
  unawaited(_finishNotificationSetup());
}

/// The slower half of push-notification setup (permission prompt, FCM
/// listeners, local-notifications plugin, and syncing the device token to
/// the server). Split out of main() so it can run after runApp() instead of
/// blocking the first frame -- see the call site's comment.
Future<void> _finishNotificationSetup() async {
  try {
    await NotificationService.initialize();
    // This half touches FirebaseMessaging.instance immediately and must not
    // run until Firebase is actually ready (see its doc comment) -- true
    // here since it only runs after Firebase.initializeApp() above succeeded.
    FcmTokenService.initTokenRefreshListener();
    // Belt-and-braces: don't rely solely on the auth listener above having
    // caught the right event -- explicitly sync once the token is actually
    // obtainable (it isn't until Firebase/APNs init has completed).
    await FcmTokenService.sync();
  } catch (e, st) {
    debugPrint('Push notification init failed: $e');
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
}
