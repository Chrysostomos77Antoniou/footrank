import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/models/match_payment_model.dart';

MatchPaymentModel payment({
  String status = 'pending',
  int amountCents = 200,
  String currency = 'eur',
  String? failureReason,
  String? paidAt,
}) =>
    MatchPaymentModel.fromJson({
      'id': 'p1',
      'match_id': 'm1',
      'team_id': 't1',
      'captain_id': 'c1',
      'amount_cents': amountCents,
      'currency': currency,
      'status': status,
      'failure_reason': failureReason,
      'created_at': '2026-09-15T10:00:00Z',
      'paid_at': paidAt,
    });

void main() {
  group('MatchPaymentModel.fromJson', () {
    test('maps snake_case columns and parses timestamps', () {
      final p = payment(status: 'succeeded', paidAt: '2026-09-15T11:30:00Z');
      expect(p.matchId, 'm1');
      expect(p.teamId, 't1');
      expect(p.captainId, 'c1');
      expect(p.status, 'succeeded');
      expect(p.paidAt, DateTime.parse('2026-09-15T11:30:00Z'));
      expect(p.refundedAt, isNull);
    });

    test('defaults a missing amount/currency to the EUR2 fee', () {
      final p = MatchPaymentModel.fromJson({
        'id': 'p1',
        'match_id': 'm1',
        'team_id': 't1',
        'captain_id': 'c1',
        'status': 'pending',
        'created_at': '2026-09-15T10:00:00Z',
      });
      expect(p.amountCents, 200);
      expect(p.currency, 'eur');
    });

    test('status helpers are mutually exclusive', () {
      expect(payment(status: 'succeeded').isPaid, isTrue);
      expect(payment(status: 'succeeded').hasFailed, isFalse);
      expect(payment(status: 'pending').isPending, isTrue);
      expect(payment(status: 'failed').hasFailed, isTrue);
      expect(payment(status: 'refunded').isRefunded, isTrue);
      // A refunded fee must not read as paid -- the fee card decides whether to
      // ask for money again off exactly this.
      expect(payment(status: 'refunded').isPaid, isFalse);
    });
  });

  group('amount formatting', () {
    test('renders cents as a currency amount', () {
      expect(payment().amountLabel, '€2.00');
      expect(payment(amountCents: 250).amountLabel, '€2.50');
      expect(payment(amountCents: 1000).amountLabel, '€10.00');
    });

    test('honours the currency the server charged in', () {
      expect(payment(currency: 'gbp').amountLabel, '£2.00');
      expect(payment(currency: 'usd').amountLabel, '\$2.00');
    });

    test('falls back to the code for an unmapped currency', () {
      expect(payment(currency: 'sek').amountLabel, 'SEK 2.00');
    });
  });

  group('paymentResultMessage', () {
    test('covers every outcome', () {
      // Guards against a new PaymentOutcome being added without a message,
      // which would otherwise only show up as a blank toast in production.
      for (final outcome in PaymentOutcome.values) {
        final message = paymentResultMessage(PaymentResult(outcome));
        if (outcome == PaymentOutcome.cancelled) {
          expect(message, isEmpty, reason: 'cancelling is silent');
        } else {
          expect(message, isNotEmpty, reason: 'missing message for $outcome');
        }
      }
    });

    test('prefers the specific decline reason when there is one', () {
      const result = PaymentResult(
        PaymentOutcome.failed,
        'Your card has insufficient funds.',
      );
      expect(paymentResultMessage(result), 'Your card has insufficient funds.');
    });

    test('falls back to a generic message when Stripe gave no reason', () {
      const result = PaymentResult(PaymentOutcome.failed);
      expect(paymentResultMessage(result), contains('try again'));
    });
  });
}
