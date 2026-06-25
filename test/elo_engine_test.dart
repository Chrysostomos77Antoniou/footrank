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

    test('forHome treats a 0-0 result as a draw', () {
      // Common scoreless result; boundary where homeScore == awayScore == 0.
      expect(MatchResult.forHome(0, 0), MatchResult.draw);
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

    test('teamRating with a non-integer average is pinned (locks .round())', () {
      // (1500 + 1501 + 1502) / 3 = 1501.0 exactly -> 1501.
      expect(EloEngine.teamRating([1500, 1501, 1502]), 1501);
      // A genuinely fractional average rounds to nearest int.
      // (1500 + 1500 + 1502) / 3 = 1500.666... -> 1501.
      expect(EloEngine.teamRating([1500, 1500, 1502]), 1501);
      // (1500 + 1500 + 1501) / 3 = 1500.333... -> 1500.
      expect(EloEngine.teamRating([1500, 1500, 1501]), 1500);
    });

    test('win/loss deltas are equal and opposite for equal ratings', () {
      final winnerGain = EloEngine.delta(
        currentRating: 1500,
        opponentRating: 1500,
        result: MatchResult.win,
        matchType: 'ranked',
      );
      final loserDrop = EloEngine.delta(
        currentRating: 1500,
        opponentRating: 1500,
        result: MatchResult.loss,
        matchType: 'ranked',
      );
      expect(winnerGain, 20);
      expect(loserDrop, -20);
      expect(winnerGain, -loserDrop);
    });

    test('win/loss rounding is pinned for unequal ratings (rating economics)', () {
      // A=1500 beats B=1600, and B=1600 loses to A=1500.
      final winnerGain = EloEngine.delta(
        currentRating: 1500,
        opponentRating: 1600,
        result: MatchResult.win,
        matchType: 'ranked',
      );
      final loserDrop = EloEngine.delta(
        currentRating: 1600,
        opponentRating: 1500,
        result: MatchResult.loss,
        matchType: 'ranked',
      );
      // Pin the exact deltas so a future refactor cannot silently change the
      // rounding direction and therefore the rating economics.
      expect(winnerGain, 26);
      expect(loserDrop, -26);
      // The current implementation uses symmetric (half-away-from-zero)
      // rounding via num.round(), so win/loss is zero-sum here.
      expect(winnerGain, -loserDrop);
    });

    test('huge rating gap clamps probability, not the K-bounded delta', () {
      // expectedScore(1000, 2000) ~ 0.0, so a win yields nearly the full K.
      final underdogWin = EloEngine.delta(
        currentRating: 1000,
        opponentRating: 2000,
        result: MatchResult.win,
        matchType: 'ranked',
      );
      expect(underdogWin, inInclusiveRange(35, 40));

      // A heavy favourite losing drops nearly the full K.
      final favouriteLoss = EloEngine.delta(
        currentRating: 2000,
        opponentRating: 1000,
        result: MatchResult.loss,
        matchType: 'ranked',
      );
      expect(favouriteLoss, inInclusiveRange(-40, -35));
    });

    test('a draw against a much weaker team is a net loss', () {
      final d = EloEngine.delta(
        currentRating: 1800,
        opponentRating: 1200,
        result: MatchResult.draw,
        matchType: 'ranked',
      );
      expect(d, lessThan(0));
    });
  });
}
