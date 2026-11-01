// The "Pitch Power at stake" panel. Two things matter:
//  * what a captain reads: three outcomes, signed, with a real minus sign, and
//    nothing at all (not even an empty gap) while there is no answer;
//  * that the server is asked about BOTH teams. The panel used to ask an
//    opponent-blind function, so it always showed the generic +-40 (or +-20)
//    and never what that particular match was worth.
// The first half drives the widget through its loader seam. The second half
// runs the real TeamRepository against a faked transport and pins the RPC name
// and the parameter keys, because that wiring is where the bug was.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/widgets/pitch_power_preview.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real minus sign, not a hyphen.
const _minus = '−';

typedef _Call = ({String teamId, String matchType, String? opponentTeamId});

/// Records what it was asked and always answers +47 / 0 / -34.
class _Loader {
  final PitchPowerDeltas deltas = const (win: 47, draw: 0, loss: -34);
  final calls = <_Call>[];

  Future<PitchPowerDeltas> call({
    required String teamId,
    required String matchType,
    String? opponentTeamId,
  }) async {
    calls.add((
      teamId: teamId,
      matchType: matchType,
      opponentTeamId: opponentTeamId,
    ));
    return deltas;
  }
}

PitchPowerLoader _answering(Future<PitchPowerDeltas> Function() answer) =>
    ({
      required String teamId,
      required String matchType,
      String? opponentTeamId,
    }) =>
        answer();

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [child]),
        ),
      ),
    );

http.Response _json(http.Request request, Object? body) => http.Response(
      jsonEncode(body),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PitchPowerPreview', () {
    testWidgets('shows win, draw and loss, signed, with a real minus sign',
        (t) async {
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
        loader: _Loader().call,
      )));
      await t.pumpAndSettle();

      expect(find.text('Pitch Power at stake'), findsOneWidget);
      expect(find.text('WIN'), findsOneWidget);
      expect(find.text('DRAW'), findsOneWidget);
      expect(find.text('LOSS'), findsOneWidget);
      expect(find.text('+47'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('${_minus}34'), findsOneWidget);
      expect(find.text('-34'), findsNothing);
    });

    testWidgets('says the numbers are based on both teams only when it knows '
        'the opponent', (t) async {
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        matchType: 'ranked',
        loader: _Loader().call,
      )));
      await t.pumpAndSettle();
      expect(find.textContaining('Based on both teams'), findsNothing);

      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
        loader: _Loader().call,
      )));
      await t.pumpAndSettle();
      expect(find.textContaining('Based on both teams'), findsOneWidget);
    });

    testWidgets('asks about this team, this match type and the opponent',
        (t) async {
      final loader = _Loader();
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'casual',
        loader: loader.call,
      )));
      await t.pumpAndSettle();

      expect(loader.calls, [
        (teamId: 'my', matchType: 'casual', opponentTeamId: 'opp'),
      ]);
    });

    testWidgets('asks again, and shows the new numbers, when the opponent '
        'changes; and not when nothing did', (t) async {
      Future<PitchPowerDeltas> byOpponent({
        required String teamId,
        required String matchType,
        String? opponentTeamId,
      }) async =>
          opponentTeamId == 'much-stronger'
              ? (win: 60, draw: 0, loss: -27)
              : (win: 40, draw: 0, loss: -40);

      final asked = <String?>[];
      PitchPowerLoader counting() => ({
            required String teamId,
            required String matchType,
            String? opponentTeamId,
          }) {
            asked.add(opponentTeamId);
            return byOpponent(
              teamId: teamId,
              matchType: matchType,
              opponentTeamId: opponentTeamId,
            );
          };

      Widget panel(String opponent) => _host(PitchPowerPreview(
            teamId: 'my',
            opponentTeamId: opponent,
            matchType: 'ranked',
            loader: counting(),
          ));

      await t.pumpWidget(panel('level'));
      await t.pumpAndSettle();
      expect(find.text('+40'), findsOneWidget);
      expect(find.text('${_minus}40'), findsOneWidget);

      // Rebuilt with the same inputs: no second request.
      await t.pumpWidget(panel('level'));
      await t.pumpAndSettle();
      expect(asked, ['level']);

      await t.pumpWidget(panel('much-stronger'));
      await t.pumpAndSettle();
      expect(asked, ['level', 'much-stronger']);
      expect(find.text('+60'), findsOneWidget);
      expect(find.text('${_minus}27'), findsOneWidget);
      expect(find.text('+40'), findsNothing);
    });

    testWidgets('takes no room until the numbers arrive, then fits in',
        (t) async {
      final answer = Completer<PitchPowerDeltas>();
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
        loader: _answering(() => answer.future),
      )));
      await t.pump();

      expect(t.getSize(find.byType(PitchPowerPreview)).height, 0);
      expect(find.text('Pitch Power at stake'), findsNothing);

      answer.complete((win: 47, draw: 0, loss: -34));
      await t.pumpAndSettle();

      expect(t.getSize(find.byType(PitchPowerPreview)).height, greaterThan(0));
      expect(find.text('+47'), findsOneWidget);
    });

    testWidgets('stays out of the way when the server has no answer',
        (t) async {
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
        loader: _answering(
          () => Future.error(StateError('No Pitch Power preview available')),
        ),
      )));
      await t.pumpAndSettle();

      expect(find.text('Pitch Power at stake'), findsNothing);
      expect(t.getSize(find.byType(PitchPowerPreview)).height, 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('speaks each outcome in words', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
        loader: _Loader().call,
      )));
      await t.pumpAndSettle();

      expect(find.bySemanticsLabel('Win, plus 47 points'), findsOneWidget);
      expect(find.bySemanticsLabel('Draw, no change'), findsOneWidget);
      expect(find.bySemanticsLabel('Loss, minus 34 points'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('draws its own card, unless it is compact (inside a dialog)',
        (t) async {
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
        loader: _Loader().call,
      )));
      await t.pumpAndSettle();
      expect(find.byType(GlassCard), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_host(PitchPowerPreview(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
        compact: true,
        loader: _Loader().call,
      )));
      await t.pumpAndSettle();
      expect(find.byType(GlassCard), findsNothing);
      expect(find.text('+47'), findsOneWidget);
    });

    testWidgets('eases in, but shows at once under reduced motion', (t) async {
      double opacity() => t
          .widget<Opacity>(find
              .descendant(
                of: find.byType(TweenAnimationBuilder<double>),
                matching: find.byType(Opacity),
              )
              .first)
          .opacity;

      Widget panel({required bool reduceMotion}) => _host(
            PitchPowerPreview(
              teamId: 'my',
              opponentTeamId: 'opp',
              matchType: 'ranked',
              loader: _Loader().call,
            ),
            reduceMotion: reduceMotion,
          );

      await t.pumpWidget(panel(reduceMotion: false));
      await t.pump();
      expect(opacity(), lessThan(1));
      await t.pumpAndSettle();
      expect(opacity(), 1);

      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(panel(reduceMotion: true));
      await t.pump();
      expect(opacity(), 1);
    });
  });

  group('TeamRepository.previewRatingDelta (real client, faked transport)', () {
    late Future<http.Response> Function(http.Request) handler;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await SupabaseService.initialize(
        httpClient: MockClient((request) => handler(request)),
      );
    });

    test('without an opponent it asks the opponent-blind function, as older '
        'builds do', () async {
      http.Request? sent;
      handler = (request) async {
        sent = request;
        return _json(request, [
          {'win_delta': 40, 'draw_delta': 0, 'loss_delta': -40},
        ]);
      };

      final deltas = await TeamRepository()
          .previewRatingDelta(teamId: 'my', matchType: 'ranked');

      expect(sent!.method, 'POST');
      expect(sent!.url.path, endsWith('/rpc/preview_team_rating_delta'));
      expect(jsonDecode(sent!.body), {
        'p_team_id': 'my',
        'p_match_type': 'ranked',
      });
      expect(deltas, (win: 40, draw: 0, loss: -40));
    });

    test('with an opponent it asks for what THIS match is worth', () async {
      http.Request? sent;
      handler = (request) async {
        sent = request;
        return _json(request, [
          {'win_delta': 47, 'draw_delta': 0, 'loss_delta': -34},
        ]);
      };

      final deltas = await TeamRepository().previewRatingDelta(
        teamId: 'my',
        opponentTeamId: 'opp',
        matchType: 'ranked',
      );

      expect(sent!.method, 'POST');
      expect(sent!.url.path, endsWith('/rpc/preview_match_rating_delta'));
      expect(jsonDecode(sent!.body), {
        'p_team_id': 'my',
        'p_opponent_team_id': 'opp',
        'p_match_type': 'ranked',
      });
      expect(deltas, (win: 47, draw: 0, loss: -34));
    });

    test('an empty answer is an error, so the panel hides instead of '
        'inventing numbers', () async {
      handler = (request) async => _json(request, <Object>[]);

      await expectLater(
        TeamRepository().previewRatingDelta(
          teamId: 'my',
          opponentTeamId: 'unknown',
          matchType: 'ranked',
        ),
        throwsStateError,
      );
    });
  });
}
