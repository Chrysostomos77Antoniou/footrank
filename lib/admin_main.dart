import 'package:flutter/material.dart';
import 'package:footrank/admin/app.dart';
import 'package:footrank/services/supabase_service.dart';

/// Entry point for the admin web panel -- a distinct build target from the
/// main app (`flutter build web -t lib/admin_main.dart`), deployed to its
/// own private URL and never bundled into the mobile app regular users
/// install. No Firebase/push notifications, no video splash, no
/// onboarding -- none of that applies to an internal tool.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const AdminApp());
}
