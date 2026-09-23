// Exercises the real ProfileRepository against the real SupabaseClient, with
// only the network transport faked (same approach as match_repository_test).
// Guards the router's profile/Pwr checks and the Home rank card: how many
// requests they make, and that their answers stay exactly what they were.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/services/supabase_service.dart';

const _userA = '00000000-0000-0000-0000-00000000000a';
const _userB = '00000000-0000-0000-0000-00000000000b';

String _b64(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

// GoTrue decodes the JWT payload but never verifies the signature client-side.
Map<String, dynamic> _session(String userId) => {
  'access_token':
      '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({'sub': userId, 'role': 'authenticated', 'aud': 'authenticated', 'exp': 9999999999})}.sig',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': 9999999999,
  'refresh_token': 'refresh-$userId',
  'user': {
    'id': userId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': '$userId@test.dev',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2020-01-01T00:00:00Z',
  },
};

Map<String, dynamic> _profileRow(String id, {bool pwrDone = false, int? elo}) =>
    {
      'id': id,
      'name': 'Player $id',
      'username': 'p$id',
      'elo': elo,
      'created_at': '2020-01-01T00:00:00Z',
      'pwr_assessment_completed_at': pwrDone ? '2026-01-01T00:00:00Z' : null,
    };

http.Response _json(http.Request req, Object? body, [int code = 200]) =>
    http.Response(
      body == null ? '' : jsonEncode(body),
      code,
      request: req,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Profile rows keyed by user id, as the fake `users` table serves them.
  late Map<String, Map<String, dynamic>> profiles;

  /// Rows the fake `users` table returns for a query with no `id` filter.
  late List<Map<String, dynamic>> allUsers;

  /// Every request made to the `users` table.
  late List<http.Request> userRequests;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize(
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/auth/v1/token')) {
          final email = (jsonDecode(req.body) as Map)['email'] as String;
          return _json(req, _session(email.split('@').first));
        }
        if (path.endsWith('/rest/v1/users')) {
          userRequests.add(req);
          final idFilter = req.url.queryParameters['id'];
          if (idFilter == null) {
            final cols = req.url.queryParameters['select']!.split(',');
            return _json(req, [
              for (final u in allUsers) {for (final c in cols) c: u[c]},
            ]);
          }
          // maybeSingle() GETs an array and reads [] as "no row".
          final row = profiles[idFilter.replaceFirst('eq.', '')];
          return _json(req, [?row]);
        }
        return _json(req, {'message': 'unexpected $path'}, 404);
      }),
    );
  });

  Future<void> signInAs(String userId) => SupabaseService.client.auth
      .signInWithPassword(email: '$userId@test.dev', password: 'pw');

  setUp(() async {
    ProfileRepository.invalidateCache();
    profiles = {};
    allUsers = [];
    userRequests = [];
    await signInAs(_userA);
    userRequests.clear();
  });

  group('router profile checks', () {
    test('finished Pwr: both checks answered from one profile fetch', () async {
      profiles[_userA] = _profileRow(_userA, pwrDone: true);
      final repo = ProfileRepository();

      expect(await repo.hasProfile(), isTrue);
      expect(await repo.hasCompletedPwrAssessment(), isTrue);
      expect(userRequests, hasLength(1));
    });

    test('unfinished Pwr: still re-checks the server, as before', () async {
      profiles[_userA] = _profileRow(_userA);
      final repo = ProfileRepository();

      expect(await repo.hasProfile(), isTrue);
      expect(await repo.hasCompletedPwrAssessment(), isFalse);
      expect(userRequests, hasLength(2));

      // Finishing the quiz is picked up on the next check, not cached as false.
      profiles[_userA] = _profileRow(_userA, pwrDone: true);
      expect(await repo.hasCompletedPwrAssessment(), isTrue);
      expect(userRequests, hasLength(3));
    });

    test('no profile yet: reports false and makes no Pwr shortcut', () async {
      final repo = ProfileRepository();

      expect(await repo.hasProfile(), isFalse);
      expect(userRequests, hasLength(1));
    });

    test(
      "a different user never reuses the previous user's Pwr result",
      () async {
        profiles[_userA] = _profileRow(_userA, pwrDone: true);
        profiles[_userB] = _profileRow(_userB);
        final repo = ProfileRepository();

        expect(await repo.hasProfile(), isTrue); // user A: quiz done
        await signInAs(_userB); // switch account before the Pwr check runs

        expect(await repo.hasCompletedPwrAssessment(), isFalse);
        expect(userRequests, hasLength(2));
        expect(userRequests.last.url.queryParameters['id'], 'eq.$_userB');
      },
    );

    test('invalidateCache drops the shortcut', () async {
      profiles[_userA] = _profileRow(_userA, pwrDone: true);
      final repo = ProfileRepository();

      await repo.hasProfile();
      ProfileRepository.invalidateCache();
      expect(await repo.hasCompletedPwrAssessment(), isTrue);
      expect(userRequests, hasLength(2));
    });
  });

  group('fetchMyRankCard', () {
    test(
      'fetches only elo and ranks exactly as before (ties, nulls, self)',
      () async {
        profiles[_userA] = _profileRow(_userA, elo: 1500);
        allUsers = [
          {'id': 'u1', 'elo': 1700}, // above
          {'id': 'u2', 'elo': 1500}, // tie -- not above
          {'id': _userA, 'elo': 1500}, // self
          {'id': 'u3', 'elo': null}, // null counts as 1500 -- not above
          {'id': 'u4', 'elo': 1501}, // above
          {'id': 'u5', 'elo': 900},
        ];

        final card = await ProfileRepository().fetchMyRankCard();

        expect(userRequests.last.url.queryParameters['select'], 'elo');
        expect(card!.rank, 3);
        expect(card.total, 6);
      },
    );

    test(
      'a null elo is still counted as 1500 when that is above the user',
      () async {
        profiles[_userA] = _profileRow(_userA, elo: 1400);
        allUsers = [
          {'id': _userA, 'elo': 1400},
          {'id': 'u1', 'elo': null},
        ];

        final card = await ProfileRepository().fetchMyRankCard();

        expect(card!.rank, 2);
        expect(card.total, 2);
      },
    );

    test('no profile: null, and the elo list is never fetched', () async {
      expect(await ProfileRepository().fetchMyRankCard(), isNull);
      expect(userRequests, hasLength(1));
    });
  });
}
