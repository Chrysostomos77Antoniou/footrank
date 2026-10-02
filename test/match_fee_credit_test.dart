import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/models/match_payment_model.dart';
import 'package:footrank/payment/data/payment_repository.dart';

MatchPaymentModel payment({required String status, String? waiverSource}) =>
    MatchPaymentModel.fromJson({
      'id': 'p1',
      'match_id': 'm1',
      'team_id': 't1',
      'captain_id': 'c1',
      'amount_cents': 200,
      'currency': 'eur',
      'status': status,
      'waiver_source': waiverSource,
      'created_at': '2026-09-15T10:00:00Z',
    });

PendingFee fee({bool waived = false, bool credited = false}) => PendingFee(
      matchId: 'm1',
      teamId: 't1',
      homeTeamName: 'Barcelona',
      awayTeamName: 'Tigers',
      scheduledAt: DateTime.utc(2026, 10, 2, 17),
      city: 'Nicosia',
      waived: waived,
      credited: credited,
    );

void main() {
  group('fee paid with a saved credit', () {
    test('is settled and identified as a credit', () {
      final p = payment(status: 'waived', waiverSource: 'credit');
      expect(p.isPaid, isTrue);
      expect(p.isWaived, isTrue);
      expect(p.isCredit, isTrue);
    });

    test('a promo waiver is not a credit', () {
      final p = payment(status: 'waived', waiverSource: 'promo');
      expect(p.isPaid, isTrue);
      expect(p.isCredit, isFalse);
    });

    test('an ordinary paid fee is not a credit', () {
      expect(payment(status: 'succeeded').isCredit, isFalse);
    });
  });

  group('PendingFee', () {
    test('a credit covers the fee: shown as Free', () {
      final f = fee(credited: true);
      expect(f.covered, isTrue);
      expect(f.amountLabel, 'Free');
    });

    test('a promo waiver covers the fee: shown as Free', () {
      expect(fee(waived: true).covered, isTrue);
      expect(fee(waived: true).amountLabel, 'Free');
    });

    test('with neither, the €2 fee is shown', () {
      final f = fee();
      expect(f.covered, isFalse);
      expect(f.amountLabel, '€2.00');
    });
  });

  test('credited outcome has its own message', () {
    expect(
      paymentResultMessage(const PaymentResult(PaymentOutcome.credited)),
      contains('credit'),
    );
  });
}
