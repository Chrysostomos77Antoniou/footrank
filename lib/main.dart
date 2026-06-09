import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:footrank/app.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/firebase_options.dart';
import 'package:footrank/services/notification_service.dart';
import 'package:footrank/services/supabase_service.dart';

/// Minimum time the branded splash stays on screen.
const _minSplash = Duration(milliseconds: 1700);

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Keep the native splash up until we explicitly remove it below.
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  final startedAt = DateTime.now();

  // Use Android's system Photo Picker (gallery grid) where available.
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) {
    picker.useAndroidPhotoPicker = true;
  }

  await themeController.load();
  await SupabaseService.initialize();

  // Firebase + push notifications (Task 11.1). Guarded so a failure here
  // never blocks the app from launching.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Firebase/notifications init failed: $e');
  }

  runApp(const FootRankApp());

  // Hold the splash for at least _minSplash so the brand is clearly visible.
  final elapsed = DateTime.now().difference(startedAt);
  final remaining = _minSplash - elapsed;
  if (remaining > Duration.zero) {
    await Future.delayed(remaining);
  }
  FlutterNativeSplash.remove();
}
