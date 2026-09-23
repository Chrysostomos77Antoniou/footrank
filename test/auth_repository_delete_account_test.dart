// main() no longer waits for the launch-time push token sync before runApp(),
// so AuthRepository.deleteAccount() waits for it instead -- otherwise that
// sync's fcm_tokens upsert could land after the account was deleted, which
// was impossible when the sync finished before the app was even on screen.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/services/fcm_token_service.dart';
import 'package:footrank/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Requests made to the delete-account Edge Function.
  final deleteRequests = <http.Request>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize(
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/functions/v1/delete-account')) {
          deleteRequests.add(req);
          return http.Response(
            '{}',
            200,
            request: req,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404, request: req);
      }),
    );
  });

  test('deleteAccount() does not run ahead of the launch token sync', () async {
    final launchSync = Completer<void>();
    FcmTokenService.trackLaunchSync(launchSync.future);

    var deleted = false;
    final deletion = AuthRepository().deleteAccount().then(
      (_) => deleted = true,
    );

    await pumpEventQueue();
    expect(deleteRequests, isEmpty);
    expect(deleted, isFalse);

    launchSync.complete();
    await deletion;
    expect(deleteRequests, hasLength(1));
    expect(deleted, isTrue);
  });
}
