// Exercises the real MatchRepository + real SupabaseClient/PostgrestClient
// request-building and response-parsing code, with only the network
// transport faked (via the httpClient seam SupabaseService.initialize
// already exposes for exactly this purpose -- see its doc comment). This
// is deliberately not a mocktail-mocked SupabaseClient: these repository
// methods are thin RPC wrappers with no branching logic of their own (the
// real dispute-detection/proposal-acceptance business logic lives entirely
// in the Postgres functions they call, not in Dart), so the only thing
// worth protecting here is the wiring -- the right function name, the
// right param keys, and correct parsing of the RPC's return value.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/services/supabase_service.dart';

// postgrest's response parser reads `response.request!.method` (see
// PostgrestBuilder._parseResponse), so a bare http.Response with no
// `request` attached throws a null-check error before your handler's
// return value is ever seen -- always build responses through this.
http.Response _jsonResponse(http.Request request, Object? body, int statusCode) {
  return http.Response(
    body == null ? '' : jsonEncode(body),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reassigned per test; the MockClient below always delegates to whatever
  // this currently points at, since Supabase.initialize can only be called
  // once for the whole test process.
  late Future<http.Response> Function(http.Request) handler;

  setUpAll(() async {
    // Supabase.initialize persists the auth session via shared_preferences,
    // which needs a platform channel that doesn't exist under plain
    // `flutter test` -- fake it, same as any other widget test that touches
    // shared_preferences.
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize(
      httpClient: MockClient((request) => handler(request)),
    );
  });

  group('MatchRepository RPC wiring', () {
    test('submitScore posts to submit_match_score with the right params and returns the parsed status', () async {
      http.Request? captured;
      handler = (req) async {
        captured = req;
        return _jsonResponse(req, 'completed', 200);
      };

      final result = await MatchRepository().submitScore(
        matchId: 'match-1',
        homeScore: 3,
        awayScore: 1,
      );

      expect(result, 'completed');
      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, endsWith('/rpc/submit_match_score'));
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body, {
        'p_match_id': 'match-1',
        'p_home_score': 3,
        'p_away_score': 1,
      });
    });

    test('acceptProposal posts to accept_match_proposal and returns the new match id', () async {
      http.Request? captured;
      handler = (req) async {
        captured = req;
        return _jsonResponse(req, 'new-match-id', 200);
      };

      final result = await MatchRepository().acceptProposal('proposal-1');

      expect(result, 'new-match-id');
      expect(captured!.url.path, endsWith('/rpc/accept_match_proposal'));
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body, {'p_proposal_id': 'proposal-1'});
    });

    test('rejectProposal posts to reject_match_proposal with the proposal id', () async {
      http.Request? captured;
      handler = (req) async {
        captured = req;
        return _jsonResponse(req, null, 204);
      };

      await MatchRepository().rejectProposal('proposal-2');

      expect(captured!.url.path, endsWith('/rpc/reject_match_proposal'));
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body, {'p_proposal_id': 'proposal-2'});
    });

    test('submitScore surfaces a server-side error (e.g. the 5-attended-players floor) rather than swallowing it', () async {
      handler = (req) async => _jsonResponse(req, {
            'message':
                'ATTENDANCE_REQUIRED: mark at least 5 attended players for your team before submitting a score',
            'code': 'P0001',
          }, 400);

      expect(
        () => MatchRepository().submitScore(matchId: 'm', homeScore: 1, awayScore: 0),
        throwsA(isA<Object>()),
      );
    });
  });
}
