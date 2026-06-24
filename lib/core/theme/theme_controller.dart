import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footrank/core/app_refresh.dart';

/// Holds the app's ThemeMode and persists it across launches.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    _mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  /// Cycles system -> light -> dark -> system.
  Future<void> toggle() async {
    final next = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }
}

/// Global singleton instance.
final themeController = ThemeController();

/// Mix into a tab page's [State] so it repaints instantly when the theme mode
/// changes OR when the user switches to it ([uiRepaint]) — without re-fetching
/// data. The page's cached futures are untouched; only the widgets rebuild.
/// Cheap even with large lists, since no network/database work happens.
mixin ThemeRepaintMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    themeController.addListener(_repaint);
    uiRepaint.addListener(_repaint);
  }

  @override
  void dispose() {
    themeController.removeListener(_repaint);
    uiRepaint.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }
}
