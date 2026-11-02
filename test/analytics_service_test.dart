import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/services/analytics_service.dart';

void main() {
  test('logging does nothing, and never throws, before analytics is enabled',
      () {
    // No Firebase app exists in tests; an enabled logger would throw here.
    expect(() => AppAnalytics.log('team_created', {'has_logo': 1}),
        returnsNormally);
  });

  test('debug builds stay off even after enable()', () {
    AppAnalytics.enable();
    expect(() => AppAnalytics.log('score_submitted'), returnsNormally);
  });
}
