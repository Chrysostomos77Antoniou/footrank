/// Match lifecycle state machine:
///   searching -> pending -> confirmed -> completed
///
/// `searching` / `pending` live on `match_requests`; `confirmed` / `completed`
/// live on `matches`. Transitions are validated via [canTransitionTo].
enum MatchStatus {
  searching,
  pending,
  confirmed,
  completed;

  static MatchStatus fromString(String value) => MatchStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => MatchStatus.searching,
      );

  String get label {
    switch (this) {
      case MatchStatus.searching:
        return 'Searching';
      case MatchStatus.pending:
        return 'Pending';
      case MatchStatus.confirmed:
        return 'Confirmed';
      case MatchStatus.completed:
        return 'Completed';
    }
  }

  static const Map<MatchStatus, List<MatchStatus>> _allowed = {
    MatchStatus.searching: [MatchStatus.pending, MatchStatus.confirmed],
    MatchStatus.pending: [MatchStatus.confirmed],
    MatchStatus.confirmed: [MatchStatus.completed],
    MatchStatus.completed: [],
  };

  bool canTransitionTo(MatchStatus next) =>
      _allowed[this]?.contains(next) ?? false;

  bool get isOpen => this == MatchStatus.searching || this == MatchStatus.pending;
  bool get isConfirmed => this == MatchStatus.confirmed;
  bool get isCompleted => this == MatchStatus.completed;
}
