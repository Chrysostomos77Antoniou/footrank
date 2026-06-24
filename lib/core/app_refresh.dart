import 'package:flutter/foundation.dart';

/// Global "pull fresh data" signal. The Sync button bumps this; every tab
/// listens and re-fetches its data so new server data appears without a
/// full app restart.
final ValueNotifier<int> appRefresh = ValueNotifier<int>(0);

void triggerAppRefresh() => appRefresh.value++;

/// Global "repaint the UI" signal — bumped when the user switches tabs so the
/// visited tab rebuilds its widgets immediately. This does NOT re-fetch data:
/// already-loaded futures are kept, only the UI is rebuilt (cheap at any scale).
final ValueNotifier<int> uiRepaint = ValueNotifier<int>(0);

void triggerUiRepaint() => uiRepaint.value++;
