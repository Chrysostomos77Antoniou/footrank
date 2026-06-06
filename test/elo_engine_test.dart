import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/services/elo_engine.dart';

void main() {
  group('EloEngine', () {
    test('equal ratings have 0.5 expected score', () {
      expect(EloEngine.expectedScore(1500, 1500), closeTo(0.5, 1e-9));
    });

    test('K-factor is 20 casual, 40 ranked', () {
      expect(EloEngine.kFactor('casual'), 20);
      expect(EloEngine.kFactor('ranked'), 40);
      expect(EloEngine.kFactor('anything'), 20);
    });

    test('win between equal players gains +K/2 (ranked)', () {
      // expected 0.5, actual 1.0 => 40 * 0.5 = 20
      final d = EloEngine.delta(
        currentRating: 1500,
        opponentRating: 1500,
        result: MatchResult.win,
        matchType: 'ranked',
      );
      expect(d, 20);
    });

    test('loss between equal players loses K/2 (casual)', () {
      // expected 0.5, actual 0.0 => 20 * -0.5 = -10
      final d = EloEngine.delta(
        currentRating: 1500,
        opponentRating: 1500,
        result: MatchResult.loss,
        matchType: 'casual',
      );
      expect(d, -10);
    });

    test('beating a stronger opponent gains more', () {
      final vsStronger = EloEngine.delta(
        currentRating: 1500,
        opponentRating: 1800,
        result: MatchResult.win,
        matchType: 'ranked',
      );
      final vsEqual = EloEngine.delta(
        currentRating: 1500,
        opponentRating: 1500,
        result: MatchResult.win,
        matchType: 'ranked',
      );
      expect(vsStronger, greaterThan(vsEqual));
    });

    test('forHome derives correct result', () {
      expect(MatchResult.forHome(3, 1), MatchResult.win);
      expect(MatchResult.forHome(1, 3), MatchResult.loss);
      expect(MatchResult.forHome(2, 2), MatchResult.draw);
    });

    test('inverse flips win/loss, keeps draw', () {
      expect(MatchResult.win.inverse, MatchResult.loss);
      expect(MatchResult.loss.inverse, MatchResult.win);
      expect(MatchResult.draw.inverse, MatchResult.draw);
    });

    test('teamRating averages active player ELOs', () {
      expect(EloEngine.teamRating([1500, 1500, 1500, 1500, 1500]), 1500);
      expect(EloEngine.teamRating([1400, 1600, 1500, 1450, 1550]), 1500);
      // rounds to nearest int
      expect(EloEngine.teamRating([1500, 1501]), 1501);
    });

    test('teamRating falls back to starting ELO when empty', () {
      expect(EloEngine.teamRating([]), EloEngine.startingElo);
    });
  });
}
