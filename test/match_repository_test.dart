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

    group('venue suggestions on proposals', () {
      test('a proposal without a venue sends exactly what it always did', () async {
        http.Request? captured;
        handler = (req) async {
          captured = req;
          return _jsonResponse(req, 'proposal-1', 200);
        };

        final id = await MatchRepository()
            .proposeMatch(requestId: 'req-1', teamId: 'team-1');

        expect(id, 'proposal-1');
        expect(captured!.url.path, endsWith('/rpc/propose_match'));
        expect(jsonDecode(captured!.body), {
          'p_request_id': 'req-1',
          'p_team_id': 'team-1',
        });
      });

      test('a blank venue is not sent at all', () async {
        http.Request? captured;
        handler = (req) async {
          captured = req;
          return _jsonResponse(req, 'proposal-1', 200);
        };

        await MatchRepository().proposeMatch(
          requestId: 'req-1',
          teamId: 'team-1',
          venueText: '   ',
        );

        expect(jsonDecode(captured!.body), {
          'p_request_id': 'req-1',
          'p_team_id': 'team-1',
        });
      });

      test('a typed venue travels with the plain proposal, trimmed', () async {
        http.Request? captured;
        handler = (req) async {
          captured = req;
          return _jsonResponse(req, 'proposal-2', 200);
        };

        await MatchRepository().proposeMatch(
          requestId: 'req-1',
          teamId: 'team-1',
          venueText: '  Seaside Pitch ',
        );

        expect(captured!.url.path, endsWith('/rpc/propose_match'));
        expect(jsonDecode(captured!.body), {
          'p_request_id': 'req-1',
          'p_team_id': 'team-1',
          'p_venue_text': 'Seaside Pitch',
        });
      });

      test('a typed venue travels with the roster proposal too', () async {
        http.Request? captured;
        handler = (req) async {
          captured = req;
          return _jsonResponse(req, 'proposal-3', 200);
        };

        await MatchRepository().proposeMatch(
          requestId: 'req-1',
          teamId: 'team-1',
          rosterUserIds: ['u1', 'u2', 'u3', 'u4', 'u5'],
          venueText: 'Γήπεδο Κέντρο',
        );

        expect(captured!.url.path, endsWith('/rpc/propose_match_with_roster'));
        expect(jsonDecode(captured!.body), {
          'p_request_id': 'req-1',
          'p_team_id': 'team-1',
          'p_roster_user_ids': ['u1', 'u2', 'u3', 'u4', 'u5'],
          'p_venue_text': 'Γήπεδο Κέντρο',
        });
      });

      test('the server refusing a venue reaches the caller', () async {
        handler = (req) async => _jsonResponse(req, {
              'message': 'bad_venue:contact',
              'code': 'P0001',
            }, 400);

        expect(
          () => MatchRepository().proposeMatch(
            requestId: 'req-1',
            teamId: 'team-1',
            venueText: 'call 99123456',
          ),
          throwsA(isA<Object>()),
        );
      });

      test('reporting a suggested venue sends only the proposal id', () async {
        http.Request? captured;
        handler = (req) async {
          captured = req;
          return _jsonResponse(req, null, 204);
        };

        await MatchRepository().reportVenue(proposalId: 'prop-1');

        expect(captured!.url.path, endsWith('/rpc/report_venue'));
        expect(jsonDecode(captured!.body), {
          'p_request_id': null,
          'p_match_id': null,
          'p_proposal_id': 'prop-1',
        });
      });

      test('reporting a request or a match keeps the payload it always had', () async {
        final bodies = <Object?>[];
        handler = (req) async {
          bodies.add(jsonDecode(req.body));
          return _jsonResponse(req, null, 204);
        };

        await MatchRepository().reportVenue(requestId: 'req-1');
        await MatchRepository().reportVenue(matchId: 'match-1');

        expect(bodies, [
          {'p_request_id': 'req-1', 'p_match_id': null},
          {'p_request_id': null, 'p_match_id': 'match-1'},
        ]);
      });

      test('reporting needs exactly one target', () async {
        handler = (req) async => _jsonResponse(req, null, 204);
        expect(() => MatchRepository().reportVenue(), throwsA(isA<AssertionError>()));
        expect(
          () => MatchRepository()
              .reportVenue(requestId: 'req-1', proposalId: 'prop-1'),
          throwsA(isA<AssertionError>()),
        );
      });

      test('sent proposals ask for the request venue and parse both venues', () async {
        http.Request? captured;
        handler = (req) async {
          captured = req;
          return _jsonResponse(req, [
            {
              'id': 'prop-1',
              'request_id': 'req-1',
              'proposing_team_id': 'team-1',
              'proposing_user_id': 'user-1',
              'status': 'pending',
              'created_at': '2026-10-30T10:00:00Z',
              'resolved_at': null,
              'venue_text': 'Seaside Pitch',
              'match_requests': {
                'city': 'Larnaca',
                'scheduled_at': '2026-11-02T16:00:00Z',
                'match_type': 'casual',
                'format': '5v5',
                'venue_text': 'Their Home Ground',
                'teams': {'name': 'Anorthosis', 'rating': 1500, 'logo_url': null},
              },
            },
            {
              'id': 'prop-2',
              'request_id': 'req-2',
              'proposing_team_id': 'team-1',
              'proposing_user_id': 'user-1',
              'status': 'pending',
              'created_at': '2026-10-30T09:00:00Z',
              'resolved_at': null,
              'venue_text': null,
              'match_requests': {
                'city': 'Larnaca',
                'scheduled_at': '2026-11-03T16:00:00Z',
                'match_type': 'ranked',
                'format': '5v5',
                'venue_text': null,
                'teams': {'name': 'Apollon', 'rating': 1450, 'logo_url': null},
              },
            },
          ], 200);
        };

        final sent = await MatchRepository().fetchSentProposals('team-1');

        expect(captured!.url.path, endsWith('/match_request_proposals'));
        expect(captured!.url.queryParameters['select'], contains('venue_text'));
        expect(sent, hasLength(2));
        expect(sent[0].venueText, 'Seaside Pitch');
        expect(sent[0].hasVenueSuggestion, isTrue);
        expect(sent[0].requestVenueText, 'Their Home Ground');
        expect(sent[0].targetTeamName, 'Anorthosis');
        expect(sent[1].venueText, isNull);
        expect(sent[1].hasVenueSuggestion, isFalse);
        expect(sent[1].requestVenueText, isNull);
      });

      test('incoming proposals carry the suggested venue', () async {
        final seen = <String>[];
        handler = (req) async {
          seen.add(req.url.path);
          if (req.url.path.endsWith('/match_requests')) {
            return _jsonResponse(req, [
              {
                'id': 'req-1',
                'team_id': 'team-9',
                'captain_id': 'cap-9',
                'city': 'Larnaca',
                'scheduled_at': '2026-11-02T16:00:00Z',
                'match_type': 'casual',
                'format': '5v5',
                'status': 'searching',
                'created_at': '2026-10-30T10:00:00Z',
                'venue_text': 'My Ground',
              },
            ], 200);
          }
          return _jsonResponse(req, [
            {
              'id': 'prop-1',
              'request_id': 'req-1',
              'proposing_team_id': 'team-1',
              'proposing_user_id': 'user-1',
              'status': 'pending',
              'created_at': '2026-10-30T10:00:00Z',
              'resolved_at': null,
              'venue_text': 'Seaside Pitch',
              'teams': {'name': 'Keravnos', 'rating': 1500, 'logo_url': null},
            },
          ], 200);
        };

        final map = await MatchRepository().fetchProposalsForTeamRequests('team-9');

        expect(map.keys, ['req-1']);
        expect(map['req-1']!.single.venueText, 'Seaside Pitch');
        expect(map['req-1']!.single.teamName, 'Keravnos');
      });
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
