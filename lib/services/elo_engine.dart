import 'dart:math';

/// Outcome of a match from one side's perspective.
enum MatchResult {
  win(1.0),
  draw(0.5),
  loss(0.0);

  final double score;
  const MatchResult(this.score);

  /// Derives the home side's result from a final score.
  static MatchResult forHome(int homeScore, int awayScore) {
    if (homeScore > awayScore) return MatchResult.win;
    if (homeScore < awayScore) return MatchResult.loss;
    return MatchResult.draw;
  }

  MatchResult get inverse {
    switch (this) {
      case MatchResult.win:
        return MatchResult.loss;
      case MatchResult.loss:
        return MatchResult.win;
      case MatchResult.draw:
        return MatchResult.draw;
    }
  }
}

/// Standard ELO rating engine.
///
/// Starting rating is 1500. K-factor is 20 for casual matches and 40 for
/// ranked matches. Rating changes are only meant to be applied to players
/// who actually attended (enforced by the caller, see Task 7.3).
class EloEngine {
  static const int startingElo = 1500;
  static const int kCasual = 20;
  static const int kRanked = 40;

  const EloEngine._();

  /// K-factor for the given match type ('ranked' => 40, otherwise 20).
  static int kFactor(String matchType) =>
      matchType == 'ranked' ? kRanked : kCasual;

  /// Team rating = average ELO of the active (attended) players in a match
  /// (5 for a 5v5). Falls back to [startingElo] when no players are given.
  static int teamRating(Iterable<int> activePlayerElos) {
    final list = activePlayerElos.toList();
    if (list.isEmpty) return startingElo;
    final sum = list.reduce((a, b) => a + b);
    return (sum / list.length).round();
  }

  /// Expected score (win probability) for [playerRating] against
  /// [opponentRating], in the range 0..1.
  static double expectedScore(int playerRating, int opponentRating) =>
      1.0 / (1.0 + pow(10, (opponentRating - playerRating) / 400.0));

  /// New rating for a player after a match.
  static int newRating({
    required int currentRating,
    required int opponentRating,
    required MatchResult result,
    required String matchType,
  }) {
    final expected = expectedScore(currentRating, opponentRating);
    final k = kFactor(matchType);
    return (currentRating + k * (result.score - expected)).round();
  }

  /// Rating change (can be negative) for a player after a match.
  static int delta({
    required int currentRating,
    required int opponentRating,
    required MatchResult result,
    required String matchType,
  }) =>
      newRating(
        currentRating: currentRating,
        opponentRating: opponentRating,
        result: result,
        matchType: matchType,
      ) -
      currentRating;
}
