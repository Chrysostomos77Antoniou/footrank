import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/match/presentation/pages/match_detail_page.dart';

void main() {
  group('scoreSubmitMessage', () {
    test('completed -> agreement message', () {
      expect(
        scoreSubmitMessage('completed'),
        'Both captains agree on the winner — match completed!',
      );
    });

    test('disputed -> ask captain to re-check and re-submit', () {
      expect(
        scoreSubmitMessage('disputed'),
        'Your report disagrees with the opponent on the winner. '
            'Please check and re-submit.',
      );
    });

    test('resolved -> auto-resolved-in-favour-of-trusted-captain message', () {
      expect(
        scoreSubmitMessage('resolved'),
        'Still disagreeing — resolved automatically in favour of the more '
            'trusted captain. Match completed.',
      );
    });

    test('awaiting_opponent -> waiting message', () {
      expect(
        scoreSubmitMessage('awaiting_opponent'),
        'Score submitted. Waiting for the opponent\'s report.',
      );
    });

    test('unknown status falls back to the waiting message rather than throwing', () {
      expect(
        scoreSubmitMessage('some_future_status_this_test_does_not_know_about'),
        'Score submitted. Waiting for the opponent\'s report.',
      );
    });
  });
}
