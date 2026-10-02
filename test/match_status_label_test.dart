import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/models/match_status.dart';

void main() {
  group('matchStatusLabel', () {
    test('confirmed but unpaid reads Awaiting payment', () {
      for (final payment in ['unpaid', 'awaiting_payment']) {
        expect(
          matchStatusLabel(MatchStatus.confirmed,
              paymentStatus: payment, paymentsEnabled: true),
          'Awaiting payment',
        );
      }
    });

    test('confirmed and fully paid reads Confirmed', () {
      expect(
        matchStatusLabel(MatchStatus.confirmed,
            paymentStatus: 'paid', paymentsEnabled: true),
        'Confirmed',
      );
    });

    test('with payments disabled it stays Confirmed', () {
      expect(
        matchStatusLabel(MatchStatus.confirmed,
            paymentStatus: 'unpaid', paymentsEnabled: false),
        'Confirmed',
      );
    });

    test('other states are unchanged', () {
      for (final s in [
        MatchStatus.searching,
        MatchStatus.pending,
        MatchStatus.completed,
      ]) {
        expect(
          matchStatusLabel(s,
              paymentStatus: 'unpaid', paymentsEnabled: true),
          s.label,
        );
      }
    });
  });
}
