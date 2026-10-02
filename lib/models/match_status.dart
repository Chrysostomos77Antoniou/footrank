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

/// What to call a match in the UI.
///
/// A match only becomes `confirmed` once both captains agree, but with match
/// fees on it is not actually *settled* until both teams have paid -- if one
/// team hasn't, the payment-deadline job cancels it. Showing "Confirmed" while
/// a fee is still outstanding told the team that had already paid that
/// everything was done, so a confirmed-but-unpaid match reads "Awaiting
/// payment" instead.
///
/// [paymentStatus] is the match-wide value (`unpaid | awaiting_payment | paid`).
/// [paymentsEnabled] is false in builds without a Stripe key, where nobody can
/// pay and "Awaiting payment" would be a lie.
String matchStatusLabel(
  MatchStatus status, {
  required String paymentStatus,
  required bool paymentsEnabled,
}) {
  if (status == MatchStatus.confirmed &&
      paymentsEnabled &&
      paymentStatus != 'paid') {
    return 'Awaiting payment';
  }
  return status.label;
}
