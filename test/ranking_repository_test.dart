// Exercises the real RankingRepository + real SupabaseClient/PostgrestClient
// request-building and response-parsing code, with only the network
// transport faked (same approach as match_repository_test.dart). What's
// worth protecting here is the query wiring: fetchPlayers must request an
// explicit, public-safe column list from `users` (never a bare SELECT *,
// which would leak any column later added to the table), while keeping the
// leaderboard's filters/ordering and UserModel parsing unchanged.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/rankings/data/ranking_repository.dart';
import 'package:footrank/services/supabase_service.dart';

// See match_repository_test.dart: postgrest reads `response.request!.method`,
// so responses must carry the originating request.
http.Response _jsonResponse(http.Request request, Object? body, int statusCode) {
  return http.Response(
    body == null ? '' : jsonEncode(body),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

/// Every key UserModel.fromJson reads. Spelled out here (rather than derived
/// from ProfileRepository.publicColumns) so dropping a column from that list
/// -- or quietly widening it -- fails this test.
const _userModelColumns = {
  'id',
  'name',
  'username',
  'city',
  'position',
  'elo',
  'reliability',
  'behavior_positive',
  'behavior_negative',
  'matches_played',
  'avatar_url',
  'dispute_count',
  'flagged',
  'created_at',
  'pwr_assessment_completed_at',
};

Map<String, dynamic> _userRow(String id, {required int elo, String? position}) => {
      'id': id,
      'name': 'Player $id',
      'username': 'player_$id',
      'city': 'Nicosia',
      'position': position,
      'elo': elo,
      'reliability': 95,
      'behavior_positive': 4,
      'behavior_negative': 1,
      'matches_played': 7,
      'avatar_url': 'https://example.com/$id.png',
      'dispute_count': 1,
      'flagged': false,
      'created_at': '2026-01-02T03:04:05Z',
      'pwr_assessment_completed_at': '2026-01-03T00:00:00Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Future<http.Response> Function(http.Request) handler;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize(
      httpClient: MockClient((request) => handler(request)),
    );
  });

  group('RankingRepository.fetchPlayers', () {
    test('selects exactly the public-safe UserModel columns, never SELECT *', () async {
      http.Request? captured;
      handler = (req) async {
        captured = req;
        return _jsonResponse(req, <Object>[], 200);
      };

      await RankingRepository().fetchPlayers();

      expect(captured, isNotNull);
      expect(captured!.method, 'GET');
      expect(captured!.url.path, endsWith('/users'));
      final select = captured!.url.queryParameters['select'];
      expect(select, ProfileRepository.publicColumns);
      expect(select, isNot('*'));
      expect(select!.split(',').toSet(), _userModelColumns);
    });

    test('keeps the min-matches filter and elo-desc ordering, no position filter by default', () async {
      http.Request? captured;
      handler = (req) async {
        captured = req;
        return _jsonResponse(req, <Object>[], 200);
      };

      await RankingRepository().fetchPlayers();

      final params = captured!.url.queryParameters;
      expect(params['matches_played'], 'gte.${RankingRepository.minMatches}');
      expect(params['order'], startsWith('elo.desc'));
      expect(params.containsKey('position'), isFalse);
    });

    test('applies the position filter when given', () async {
      http.Request? captured;
      handler = (req) async {
        captured = req;
        return _jsonResponse(req, <Object>[], 200);
      };

      await RankingRepository().fetchPlayers(position: 'GK');

      final params = captured!.url.queryParameters;
      expect(params['position'], 'eq.GK');
      expect(params['matches_played'], 'gte.${RankingRepository.minMatches}');
      expect(params['order'], startsWith('elo.desc'));
    });

    test('parses the rows into UserModels in server order', () async {
      handler = (req) async => _jsonResponse(req, [
            _userRow('a', elo: 1720, position: 'ST'),
            _userRow('b', elo: 1610),
          ], 200);

      final players = await RankingRepository().fetchPlayers();

      expect(players.map((p) => p.id), ['a', 'b']);
      final a = players.first;
      expect(a.name, 'Player a');
      expect(a.username, 'player_a');
      expect(a.city, 'Nicosia');
      expect(a.position, 'ST');
      expect(a.elo, 1720);
      expect(a.reliability, 95);
      expect(a.behaviorPositive, 4);
      expect(a.behaviorNegative, 1);
      expect(a.matchesPlayed, 7);
      expect(a.avatarUrl, 'https://example.com/a.png');
      expect(a.disputeCount, 1);
      expect(a.flagged, isFalse);
      expect(a.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(a.pwrAssessmentCompletedAt, DateTime.utc(2026, 1, 3));
      expect(players[1].position, isNull);
    });
  });
}
