import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/profile/presentation/pages/date_of_birth_page.dart';

void main() {
  final now = DateTime(2026, 10, 18);

  test('age counts whole years and respects the birthday', () {
    expect(ageOn(DateTime(2010, 10, 18), now), 16); // birthday today
    expect(ageOn(DateTime(2010, 10, 19), now), 15); // birthday tomorrow
    expect(ageOn(DateTime(2000, 1, 1), now), 26);
    expect(ageOn(DateTime(2010, 2, 28), now), 16);
  });

  test('minimum age is 16', () {
    expect(kMinimumAge, 16);
    expect(ageOn(DateTime(2010, 10, 19), now) < kMinimumAge, isTrue);
    expect(ageOn(DateTime(2010, 10, 18), now) < kMinimumAge, isFalse);
  });
}
