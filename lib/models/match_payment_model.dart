/// One team's €2 platform fee for a match, paid by that team's captain.
///
/// This covers FootRank's own fee only — the pitch rental is settled with the
/// venue directly and never passes through the app, so a paid fee must never be
/// presented to the user as a booked or reserved pitch.
class MatchPaymentModel {
  final String id;
  final String matchId;
  final String teamId;
  final String captainId;
  final int amountCents;
  final String currency;

  /// pending | succeeded | failed | refunded. Only the Stripe webhook can move
  /// a row to `succeeded`, so this is trustworthy as a display value.
  final String status;

  /// Stripe's decline message, when [status] is `failed`.
  final String? failureReason;

  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? refundedAt;

  const MatchPaymentModel({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.captainId,
    this.amountCents = 200,
    this.currency = 'eur',
    required this.status,
    this.failureReason,
    required this.createdAt,
    this.paidAt,
    this.refundedAt,
  });

  bool get isPaid => status == 'succeeded';
  bool get isPending => status == 'pending';
  bool get hasFailed => status == 'failed';
  bool get isRefunded => status == 'refunded';

  /// `€2.00` — formatted from cents so a fee change in the Edge Function's
  /// MATCH_FEE_CENTS shows up correctly here without a client release.
  String get amountLabel => formatAmount(amountCents, currency);

  static String formatAmount(int cents, String currency) {
    final symbol = switch (currency.toLowerCase()) {
      'eur' => '€',
      'gbp' => '£',
      'usd' => '\$',
      _ => '${currency.toUpperCase()} ',
    };
    return '$symbol${(cents / 100).toStringAsFixed(2)}';
  }

  factory MatchPaymentModel.fromJson(Map<String, dynamic> json) =>
      MatchPaymentModel(
        id: json['id'] as String,
        matchId: json['match_id'] as String,
        teamId: json['team_id'] as String,
        captainId: json['captain_id'] as String,
        amountCents: (json['amount_cents'] as num?)?.toInt() ?? 200,
        currency: (json['currency'] as String?) ?? 'eur',
        status: json['status'] as String,
        failureReason: json['failure_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        paidAt: json['paid_at'] != null
            ? DateTime.parse(json['paid_at'] as String)
            : null,
        refundedAt: json['refunded_at'] != null
            ? DateTime.parse(json['refunded_at'] as String)
            : null,
      );
}

/// Outcome of a captain tapping "Pay" — what the UI needs to react to, without
/// leaking Stripe's own types into the widget layer.
enum PaymentOutcome {
  /// Charge completed. The row is only authoritative once Stripe's webhook has
  /// written it, so the UI polls briefly rather than assuming immediately.
  succeeded,

  /// The captain dismissed the Stripe sheet. Not an error — show nothing.
  cancelled,

  /// Already paid (a duplicate tap, or another device got there first).
  alreadyPaid,

  /// Card declined or the sheet failed. [PaymentResult.message] says why.
  failed,
}

class PaymentResult {
  final PaymentOutcome outcome;
  final String? message;

  const PaymentResult(this.outcome, [this.message]);

  bool get isCancelled => outcome == PaymentOutcome.cancelled;
}

/// Message shown to the captain for a given outcome.
///
/// Pulled out as a top-level pure function — like [scoreSubmitMessage] in
/// match_detail_page.dart — so a dropped case is caught by a unit test rather
/// than by someone noticing the wrong toast in production.
String paymentResultMessage(PaymentResult result) => switch (result.outcome) {
      PaymentOutcome.succeeded => 'Fee paid — your team is all set.',
      PaymentOutcome.alreadyPaid => 'This fee has already been paid.',
      PaymentOutcome.failed =>
        result.message ?? 'Payment failed. Please try again.',
      // Never surfaced: the caller returns early on a cancellation so the
      // captain isn't told off for changing their mind.
      PaymentOutcome.cancelled => '',
    };
