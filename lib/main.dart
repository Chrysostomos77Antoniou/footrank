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
  // Watch for the password-recovery deep link so we can route to the reset page.
  initPasswordRecoveryListener();

  // Must be registered right after Supabase itself initializes -- it fires
  // an `initialSession` event synchronously as part of setup, and that's a
  // broadcast stream with no replay: subscribing any later (e.g. after the
  // Firebase block below, which can take several seconds) silently misses
  // it forever for anyone whose session is being restored rather than
  // freshly signed in, so their FCM token would never get synced at all.
  FcmTokenService.init();

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
    await NotificationService.initialize();
    // Belt-and-braces: don't rely solely on the auth listener above having
    // caught the right event -- explicitly sync once the token is actually
    // obtainable (it isn't until Firebase/APNs init above has completed).
    await FcmTokenService.sync();
  } catch (e, st) {
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

  runApp(const FootRankApp());
}
