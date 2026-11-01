// Plain-Dart helpers that turn match data into the words the Matches screens
// show. No Flutter in here, so every rule can be tested without a widget tree.

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Today", "Tomorrow" or "Yesterday" when that is what it is, otherwise
/// "Sat 2 Nov" -- with the year added once it is not the current one
/// ("Sat 2 Nov 2027"). [now] exists for tests.
String formatMatchDay(DateTime when, {DateTime? now}) {
  final d = when.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  // Calendar days apart, worked out on UTC dates so a daylight-saving change
  // between the two cannot turn 24 hours into 23 or 25.
  final days = DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(n.year, n.month, n.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  return d.year == n.year ? base : '$base ${d.year}';
}

/// 24-hour clock from an hour and a minute, "18:30".
String formatClock(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// 24-hour clock, "18:30".
String formatMatchTime(DateTime when) {
  final d = when.toLocal();
  return formatClock(d.hour, d.minute);
}

/// "Tomorrow · 18:30", "Sat 2 Nov · 18:30".
String formatMatchWhen(DateTime when, {DateTime? now}) =>
    '${formatMatchDay(when, now: now)} · ${formatMatchTime(when)}';

/// The one line shown on the collapsed filter bar of the Opponents tab:
/// "Larnaca · Ranked · Tomorrow · around 18:30 · ±150 PWR". What is not set
/// reads as "Any type" / "Any date", and a time or power range that is not set
/// is left out. [hour] and [minute] come as ints to keep Flutter out of here.
String describeOpponentFilters({
  required String city,
  String? matchType,
  DateTime? date,
  int? hour,
  int? minute,
  int powerRange = 0,
  DateTime? now,
}) {
  return [
    city,
    matchType == null ? 'Any type' : matchTypeLabel(matchType),
    date == null ? 'Any date' : formatMatchDay(date, now: now),
    if (hour != null && minute != null) 'around ${formatClock(hour, minute)}',
    if (powerRange > 0) '±$powerRange PWR',
  ].join(' · ');
}

/// "Ranked" / "Casual" for the database's lower-case match types.
String matchTypeLabel(String type) {
  switch (type) {
    case 'ranked':
      return 'Ranked';
    case 'casual':
      return 'Casual';
    default:
      return type.isEmpty ? type : type[0].toUpperCase() + type.substring(1);
  }
}

/// Which side of you another team's Pitch Power sits on.
enum PowerGapKind { even, stronger, weaker }

/// How another team's Pitch Power compares with yours, in words a captain can
/// read at a glance. Informational only: nothing is blocked by it, and the
/// exact points at stake come from the server (see PitchPowerPreview).
class PowerGap {
  final PowerGapKind kind;

  /// Absolute difference in Pitch Power.
  final int points;

  const PowerGap(this.kind, this.points);

  /// Teams this close (or closer) are described as evenly matched.
  static const int evenWithin = 25;

  /// The gap from [mine] to [theirs]; null when either rating is unknown.
  static PowerGap? between({required int? mine, required int? theirs}) {
    if (mine == null || theirs == null) return null;
    final diff = theirs - mine;
    if (diff.abs() <= evenWithin) return PowerGap(PowerGapKind.even, diff.abs());
    return PowerGap(
      diff > 0 ? PowerGapKind.stronger : PowerGapKind.weaker,
      diff.abs(),
    );
  }

  /// Short form, for after a rating that already says PWR:
  /// "1780 PWR · 120 above you".
  String get label {
    switch (kind) {
      case PowerGapKind.even:
        return 'Evenly matched';
      case PowerGapKind.stronger:
        return '$points above you';
      case PowerGapKind.weaker:
        return '$points below you';
    }
  }

  /// Stand-alone form: "120 PWR above you".
  String get sentence {
    switch (kind) {
      case PowerGapKind.even:
        return 'Evenly matched';
      case PowerGapKind.stronger:
        return '$points PWR above you';
      case PowerGapKind.weaker:
        return '$points PWR below you';
    }
  }
}
