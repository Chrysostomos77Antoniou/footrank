// The words the Matches screens print: when a match is, what the filter bar
// says, how far above or below you another team is. Plain Dart, so every rule
// is checked here without a widget tree, against a fixed "now" (a Sunday).
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/match/presentation/widgets/match_formatters.dart';

/// Sunday 1 November 2026, midday.
final _now = DateTime(2026, 11, 1, 12);

void main() {
  group('formatMatchDay', () {
    test('today, tomorrow and yesterday are said as words', () {
      expect(formatMatchDay(DateTime(2026, 11, 1, 23, 59), now: _now), 'Today');
      expect(formatMatchDay(DateTime(2026, 11, 2, 0, 5), now: _now), 'Tomorrow');
      expect(
          formatMatchDay(DateTime(2026, 10, 31, 20), now: _now), 'Yesterday');
    });

    test('further away it is weekday, day and month', () {
      expect(formatMatchDay(DateTime(2026, 11, 3, 18), now: _now), 'Tue 3 Nov');
      expect(formatMatchDay(DateTime(2026, 11, 7, 18), now: _now), 'Sat 7 Nov');
      expect(
          formatMatchDay(DateTime(2026, 12, 25, 18), now: _now), 'Fri 25 Dec');
      expect(formatMatchDay(DateTime(2026, 10, 25, 18), now: _now), 'Sun 25 Oct');
    });

    test('the year is added once it is not this one', () {
      expect(formatMatchDay(DateTime(2027, 1, 2, 18), now: _now),
          'Sat 2 Jan 2027');
      expect(formatMatchDay(DateTime(2025, 12, 31, 18), now: _now),
          'Wed 31 Dec 2025');
    });

    test('"today" follows the calendar, not the clock', () {
      final lateEvening = DateTime(2026, 11, 1, 23, 59);
      expect(formatMatchDay(DateTime(2026, 11, 1, 0, 1), now: lateEvening),
          'Today');
      // Half an hour away, but already tomorrow.
      expect(formatMatchDay(DateTime(2026, 11, 2, 0, 30), now: lateEvening),
          'Tomorrow');
    });
  });

  group('clock', () {
    test('formatClock pads hours and minutes', () {
      expect(formatClock(7, 5), '07:05');
      expect(formatClock(18, 30), '18:30');
      expect(formatClock(0, 0), '00:00');
      expect(formatClock(23, 59), '23:59');
    });

    test('formatMatchTime is the 24-hour clock', () {
      expect(formatMatchTime(DateTime(2026, 11, 3, 9, 5)), '09:05');
      expect(formatMatchTime(DateTime(2026, 11, 3, 21, 45)), '21:45');
    });

    test('formatMatchWhen joins the day and the time', () {
      expect(formatMatchWhen(DateTime(2026, 11, 2, 18, 30), now: _now),
          'Tomorrow · 18:30');
      expect(formatMatchWhen(DateTime(2026, 11, 7, 20), now: _now),
          'Sat 7 Nov · 20:00');
    });
  });

  group('matchTypeLabel', () {
    test('names the two real types', () {
      expect(matchTypeLabel('ranked'), 'Ranked');
      expect(matchTypeLabel('casual'), 'Casual');
    });

    test('capitalises a type it does not know instead of hiding it', () {
      expect(matchTypeLabel('friendly'), 'Friendly');
      expect(matchTypeLabel(''), '');
    });
  });

  group('describeOpponentFilters', () {
    test('with nothing chosen it says any type and any date', () {
      expect(describeOpponentFilters(city: 'Larnaca', now: _now),
          'Larnaca · Any type · Any date');
    });

    test('with everything chosen it lists every part, in order', () {
      expect(
        describeOpponentFilters(
          city: 'Limassol',
          matchType: 'ranked',
          date: DateTime(2026, 11, 2),
          hour: 18,
          minute: 30,
          powerRange: 150,
          now: _now,
        ),
        'Limassol · Ranked · Tomorrow · around 18:30 · ±150 PWR',
      );
    });

    test('a time needs both its hour and its minute, or it is left out', () {
      expect(
        describeOpponentFilters(city: 'Larnaca', hour: 18, now: _now),
        'Larnaca · Any type · Any date',
      );
      expect(
        describeOpponentFilters(city: 'Larnaca', minute: 30, now: _now),
        'Larnaca · Any type · Any date',
      );
    });

    test('a power range of zero means any strength and is not mentioned', () {
      expect(
        describeOpponentFilters(city: 'Larnaca', powerRange: 0, now: _now),
        isNot(contains('PWR')),
      );
      expect(
        describeOpponentFilters(city: 'Larnaca', powerRange: 50, now: _now),
        endsWith('±50 PWR'),
      );
    });

    test('a date is a word when it is close and a date when it is not', () {
      expect(
        describeOpponentFilters(
            city: 'Larnaca', date: DateTime(2026, 11, 1), now: _now),
        'Larnaca · Any type · Today',
      );
      expect(
        describeOpponentFilters(
            city: 'Larnaca', date: DateTime(2026, 11, 7), now: _now),
        'Larnaca · Any type · Sat 7 Nov',
      );
    });
  });

  group('PowerGap', () {
    test('teams within 25 points of each other are evenly matched', () {
      for (final theirs in [1475, 1490, 1500, 1510, 1525]) {
        final gap = PowerGap.between(mine: 1500, theirs: theirs)!;
        expect(gap.kind, PowerGapKind.even, reason: '$theirs');
        expect(gap.label, 'Evenly matched');
        expect(gap.sentence, 'Evenly matched');
      }
    });

    test('one point further out and it is a gap', () {
      final above = PowerGap.between(mine: 1500, theirs: 1526)!;
      expect(above.kind, PowerGapKind.stronger);
      expect(above.points, 26);

      final below = PowerGap.between(mine: 1500, theirs: 1474)!;
      expect(below.kind, PowerGapKind.weaker);
      expect(below.points, 26);
    });

    test('it says which side the other team is on', () {
      final stronger = PowerGap.between(mine: 1500, theirs: 1620)!;
      expect(stronger.kind, PowerGapKind.stronger);
      expect(stronger.points, 120);
      expect(stronger.label, '120 above you');
      expect(stronger.sentence, '120 PWR above you');

      final weaker = PowerGap.between(mine: 1700, theirs: 1550)!;
      expect(weaker.kind, PowerGapKind.weaker);
      expect(weaker.points, 150);
      expect(weaker.label, '150 below you');
      expect(weaker.sentence, '150 PWR below you');
    });

    test('a huge gap is described like any other: nothing is ruled out by it',
        () {
      final gap = PowerGap.between(mine: 1500, theirs: 2100)!;
      expect(gap.kind, PowerGapKind.stronger);
      expect(gap.label, '600 above you');
    });

    test('without both ratings there is nothing to compare', () {
      expect(PowerGap.between(mine: null, theirs: 1500), isNull);
      expect(PowerGap.between(mine: 1500, theirs: null), isNull);
      expect(PowerGap.between(mine: null, theirs: null), isNull);
    });
  });
}
