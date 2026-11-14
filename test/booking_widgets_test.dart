import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/match/presentation/widgets/booking_widgets.dart';
import 'package:footrank/models/booking_models.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/team_model.dart';

MatchModel _match({
  String status = 'confirmed',
  String booking = 'not_booked',
  bool changeOpen = false,
  String? cancelReason,
}) =>
    MatchModel.fromJson({
      'id': 'm1',
      'home_team_id': 'h',
      'away_team_id': 'a',
      'city': 'Nicosia',
      'scheduled_at': DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
      'match_type': 'casual',
      'format': '5v5',
      'status': status,
      'created_at': DateTime.now().toIso8601String(),
      'venue_text': 'Court 101',
      'booker_team_id': 'h',
      'court_booking_status': booking,
      'booking_deadline_at':
          DateTime.now().add(const Duration(hours: 2, minutes: 30)).toIso8601String(),
      'venue_change_open': changeOpen,
      'cancel_reason': cancelReason,
      'home_team': {'name': 'Phoenix Rising'},
      'away_team': {'name': 'Anorthosis'},
    });

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child));

void main() {
  test('countdown text', () {
    expect(bookingCountdown(const Duration(hours: 1, minutes: 20)), '1h 20m');
    expect(bookingCountdown(const Duration(minutes: 25)), '25m');
    expect(bookingCountdown(const Duration(seconds: 20)), 'under a minute');
    expect(bookingCountdown(const Duration(minutes: -5)), 'under a minute');
  });

  test('the match reads its booking fields', () {
    final m = _match();
    expect(m.hasBookingFlow, isTrue);
    expect(m.needsBooking, isTrue);
    expect(m.bookerTeamName, 'Phoenix Rising');
    expect(m.bookingDeadlineAt, isNotNull);
  });

  testWidgets('status strip: amber, green, changing, red', (t) async {
    await t.pumpWidget(_host(BookingStatusStrip(match: _match())));
    expect(find.text('Not booked yet'), findsOneWidget);
    expect(find.text('Phoenix Rising books'), findsOneWidget);

    await t.pumpWidget(_host(BookingStatusStrip(match: _match(booking: 'booked'))));
    expect(find.text('Booked ✓'), findsOneWidget);

    await t.pumpWidget(_host(BookingStatusStrip(match: _match(changeOpen: true))));
    expect(find.text('Venue being changed'), findsOneWidget);

    await t.pumpWidget(_host(BookingStatusStrip(
        match: _match(status: 'cancelled', booking: 'cancelled_unbooked'))));
    expect(find.text('Cancelled'), findsOneWidget);
  });

  test('cancel reasons in plain words', () {
    expect(bookingCancelText('court_not_booked'),
        "Cancelled: the court wasn't confirmed as booked.");
    expect(bookingCancelText('venue_declined_3'), contains('3 declined'));
    expect(bookingCancelText('expired_no_score'), isNull);
  });

  test('timeline lines', () {
    MatchEventModel e(String type, Map<String, dynamic> p) => MatchEventModel(
        id: '1', type: type, payload: p, createdAt: DateTime(2026));
    expect(e('venue_suggested', {'venue': 'Court 101', 'team': 'Beta'}).describe(),
        'Court 101 suggested by Beta');
    expect(e('venue_declined', {'venue': 'Court 101'}).describe(), 'Court 101 declined');
    expect(e('venue_accepted', {'venue': 'Court 7'}).describe(), 'Court 7 accepted');
  });

  testWidgets('the ack row toggles', (t) async {
    var v = false;
    await t.pumpWidget(_host(StatefulBuilder(
      builder: (ctx, set) => BookingAckRow(
          value: v, onChanged: (x) => set(() => v = x), text: 'You book the court.'),
    )));
    await t.tap(find.text('You book the court.'));
    await t.pump();
    expect(v, isTrue);
  });

  testWidgets('reliability card shows the score and missed bookings', (t) async {
    await t.pumpWidget(_host(const ReliabilityCard(score: 90, missed: 1)));
    expect(find.text('Court reliability'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    expect(find.text('1 match cancelled: court not booked'), findsOneWidget);
    expect(reliabilityColor(90), isNot(reliabilityColor(40)));
  });

  test('team reads its reliability', () {
    final team = TeamModel.fromJson({
      'id': 't', 'name': 'X', 'captain_id': 'c',
      'created_at': DateTime(2026).toIso8601String(),
      'reliability_score': 80, 'unbooked_cancels': 2,
    });
    expect(team.reliabilityScore, 80);
    expect(team.unbookedCancels, 2);
    final old = TeamModel.fromJson({
      'id': 't', 'name': 'X', 'captain_id': 'c',
      'created_at': DateTime(2026).toIso8601String(),
    });
    expect(old.reliabilityScore, isNull);
  });
}
