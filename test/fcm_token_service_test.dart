// main() no longer waits for the launch-time push token sync before runApp(),
// so FcmTokenService.remove() (the first step of sign-out) waits for it
// instead -- otherwise a sign-out straight after launch could run before this
// device's token was known and leave its fcm_tokens row behind.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footrank/services/fcm_token_service.dart';
import 'package:footrank/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize(
      httpClient: MockClient((req) async => http.Response('{}', 404)),
    );
  });

  test('remove() does not run ahead of the launch token sync', () async {
    final launchSync = Completer<void>();
    FcmTokenService.trackLaunchSync(launchSync.future);

    var removed = false;
    final removal = FcmTokenService.remove().then((_) => removed = true);

    await pumpEventQueue();
    expect(removed, isFalse);

    launchSync.complete();
    await removal;
    expect(removed, isTrue);
  });
}
