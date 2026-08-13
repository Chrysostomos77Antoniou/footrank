import 'package:flutter/material.dart';
import 'package:footrank/admin/presentation/pages/admin_shell.dart';
import 'package:footrank/core/theme/app_theme.dart';

/// Root widget for the admin web panel -- a separate Flutter Web build
/// (see lib/admin_main.dart) that is never bundled into the mobile app
/// regular users install. Dark theme only; this is an internal tool, not
/// something that needs to match a visitor's system preference.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FootRank Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const AdminShell(),
    );
  }
}
