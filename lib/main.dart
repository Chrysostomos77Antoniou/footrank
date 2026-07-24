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
  } catch (e) {
    debugPrint('Firebase/notifications init failed: $e');
  }

  // Keep the user's FCM device token in sync so the server can push to them.
  FcmTokenService.init();

  runApp(const FootRankApp());
}
