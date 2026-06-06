import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:footrank/app.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/firebase_options.dart';
import 'package:footrank/services/notification_service.dart';
import 'package:footrank/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use Android's system Photo Picker (gallery grid) instead of the file picker.
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
}
