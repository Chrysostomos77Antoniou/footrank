import 'dart:async';
import 'package:flutter/foundation.dart';

class RouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  RouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
