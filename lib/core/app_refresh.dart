import 'package:flutter/foundation.dart';

/// Global "pull fresh data" signal. The Sync button bumps this; every tab
/// listens and re-fetches its data so new server data appears without a
/// full app restart.
final ValueNotifier<int> appRefresh = ValueNotifier<int>(0);

void triggerAppRefresh() => appRefresh.value++;
