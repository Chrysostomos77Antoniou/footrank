// A fake HTTP backend for integration tests. Initializing Supabase with this
// client means the real app code (repositories, auth, router) runs end-to-end
// with NO network — fully deterministic, production is never touched.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testUserId = '00000000-0000-0000-0000-000000000001';

String _b64(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

// A structurally-valid JWT (GoTrue decodes the payload; it doesn't verify the
// signature client-side, so an unsigned fake works for tests).
String _fakeJwt() {
  final header = _b64({'alg': 'HS256', 'typ': 'JWT'});
  final payload = _b64({
    'sub': testUserId,
    'role': 'authenticated',
    'aud': 'authenticated',
    'email': 'qa@test.dev',
    'exp': 9999999999,
  });
  return '$header.$payload.signature';
}

http.Client buildMockClient() {
  final jwt = _fakeJwt();
  final user = {
    'id': testUserId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'qa@test.dev',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2020-01-01T00:00:00Z',
  };
  final session = {
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': 9999999999,
    'refresh_token': 'fake-refresh-token',
    'user': user,
  };
  final profileRow = {
    'id': testUserId,
    'name': 'QA Bot',
    'username': 'qabot',
    'city': 'Testville',
    'position': 'MID',
    'created_at': '2020-01-01T00:00:00Z',
  };

  http.Response json(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

  return MockClient((req) async {
    final p = req.url.path;
    if (p.contains('/auth/v1/token')) return json(session);
    if (p.contains('/auth/v1/user')) return json(user);
    if (p.contains('/auth/v1/logout')) return http.Response('', 204);
    if (p.contains('/rest/v1/users')) return json([profileRow]);
    // Any other table query returns an empty result so screens render cleanly.
    if (p.contains('/rest/v1/')) return json([]);
    return json(<String, dynamic>{});
  });
}
