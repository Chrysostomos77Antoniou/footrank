// Behaviour of the admin "Flagged venues" screen: what each button sends to
// the server, what the admin is told, and that nothing breaks on a phone with
// large text or long Greek / emoji venue names.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/models/flagged_venue_model.dart';
import 'package:footrank/admin/presentation/pages/admin_flagged_page.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FlaggedVenueModel venue({
  String id = 'r1',
  String? requestId = 'q1',
  String? matchId,
  String? proposalId,
  String? target,
  String text = 'Seaside Pitch',
  String reason = 'no_match',
  String? status = 'searching',
  int reports = 0,
  String? suggestedId,
  String? suggestedName,
  String? suggestedCity,
  double? score,
  String team = 'Keravnos FC',
  String captain = 'Andreas',
  String city = 'Paphos',
}) =>
    FlaggedVenueModel(
      reviewId: id,
      requestId: requestId,
      matchId: matchId,
      proposalId: proposalId,
      targetTeamName: target,
      venueText: text,
      reason: reason,
      city: city,
      scheduledAt: DateTime(2026, 11, 2, 18, 30),
      teamName: team,
      captainName: captain,
      requestStatus: status,
      reportCount: reports,
      suggestedCourtId: suggestedId,
      suggestedCourtName: suggestedName,
      suggestedCourtCity: suggestedCity,
      matchScore: score,
      createdAt: DateTime(2026, 10, 30, 10),
    );

const courts = [
  AdminCourtModel(id: 'c1', name: 'Keravnos 5s', city: 'Nicosia', active: false),
  AdminCourtModel(id: 'c2', name: 'Kick On Fives', city: 'Paphos', active: false),
  AdminCourtModel(id: 'c3', name: 'Wembley', city: 'Limassol', active: false),
];

/// Behaves like the server: a reviewed row leaves the flagged list.
class RecordingRepo extends AdminRepository {
  final List<FlaggedVenueModel> items;
  final List<(String, String, String?)> calls = [];
  Object? reviewError;
  Object? fetchError;
  Completer<void>? gate;
  int fetches = 0;

  RecordingRepo(this.items);

  @override
  Future<List<FlaggedVenueModel>> fetchFlaggedVenues() async {
    fetches++;
    final e = fetchError;
    if (e != null) throw e;
    return List.of(items);
  }

  @override
  Future<List<AdminCourtModel>> fetchAllCourts() async => courts;

  @override
  Future<void> reviewVenue(
    String reviewId,
    String action, {
    String? courtId,
  }) async {
    calls.add((reviewId, action, courtId));
    await gate?.future;
    final e = reviewError;
    if (e != null) throw e;
    items.removeWhere((i) => i.reviewId == reviewId);
  }
}

Widget host(Widget child, {double textScale = 1}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: c!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: child,
          ),
        ),
      ),
    );

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> show(
  WidgetTester t,
  RecordingRepo repo, {
  double width = 390,
  double height = 780,
  double textScale = 1,
}) async {
  t.view.physicalSize = Size(width * 2, height * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(host(AdminFlaggedPage(repo: repo), textScale: textScale));
  await settle(t);
}

Finder buttonLabelled(String label) => find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<OutlinedButton>(),
    );

bool enabled(WidgetTester t, Finder f) =>
    t.widget<OutlinedButton>(f.first).onPressed != null;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('removeVenueMessage', () {
    test('an open request says it will be deleted', () {
      expect(removeVenueMessage(venue(text: 'Fake Stadium')),
          contains('will be deleted'));
    });

    test('a venue on a match says it is cleared from the match', () {
      final m = removeVenueMessage(
          venue(requestId: null, matchId: 'm1', status: 'confirmed'));
      expect(m, contains('cleared from the match'));
      expect(m, isNot(contains('deleted')));
    });

    test('a request that already became a match is cleared, not deleted', () {
      final m = removeVenueMessage(venue(status: 'pending'));
      expect(m, contains('cleared from the match'));
    });

    test('a suggestion on a proposal cancels it and leaves the request open', () {
      final m = removeVenueMessage(
          venue(requestId: null, proposalId: 'p1', text: 'Beach Arena'));
      expect(m, contains('"Beach Arena"'));
      expect(m, contains('cancelled'));
      expect(m, contains('stays open'));
      expect(m, isNot(contains('deleted')));
    });

    test('an accepted suggestion is cleared from the match like any venue', () {
      final m = removeVenueMessage(
          venue(matchId: 'm1', proposalId: 'p1', status: 'pending'));
      expect(m, contains('cleared from the match'));
    });
  });

  group('Approve', () {
    testWidgets('sends approve, drops the card, tells the admin', (t) async {
      final repo = RecordingRepo([venue()]);
      await show(t, repo);
      expect(find.text('Seaside Pitch'), findsOneWidget);

      await t.tap(find.text('Approve'));
      await settle(t);

      expect(repo.calls, [('r1', 'approve', null)]);
      expect(find.text('Seaside Pitch'), findsNothing);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.textContaining('Nothing to review'), findsOneWidget);
    });

    testWidgets('buttons are locked while the call is in flight', (t) async {
      final repo = RecordingRepo([venue()])..gate = Completer<void>();
      await show(t, repo);

      await t.tap(find.text('Approve'));
      await t.pump();
      expect(enabled(t, buttonLabelled('Approve')), isFalse);
      expect(enabled(t, buttonLabelled('Link to court')), isFalse);
      expect(enabled(t, buttonLabelled('Remove')), isFalse);
      expect(repo.calls, hasLength(1));

      repo.gate!.complete();
      await settle(t);
      expect(find.text('Seaside Pitch'), findsNothing);
    });

    testWidgets('a server refusal is shown plainly and the card stays',
        (t) async {
      final repo = RecordingRepo([venue()])
        ..reviewError = const PostgrestException(
          message: 'The venue name was changed in the meantime. '
              'Refresh the list.',
          code: 'P0001',
        );
      await show(t, repo);

      await t.tap(find.text('Approve'));
      await settle(t);

      expect(
        find.text('The venue name was changed in the meantime. '
            'Refresh the list.'),
        findsOneWidget,
      );
      expect(find.textContaining('code:'), findsNothing);
      expect(find.text('Seaside Pitch'), findsOneWidget);
      // The admin can try again.
      expect(enabled(t, buttonLabelled('Approve')), isTrue);
    });
  });

  group('Remove', () {
    Finder dialogButton(String label) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(label),
        );

    testWidgets('an open request is deleted -- the dialog says so', (t) async {
      final repo = RecordingRepo([venue(text: 'Fake Stadium')]);
      await show(t, repo);

      await t.tap(find.text('Remove'));
      await settle(t);
      expect(find.text('Remove this venue?'), findsOneWidget);
      expect(find.textContaining('will be deleted'), findsOneWidget);
      expect(find.textContaining('"Fake Stadium"'), findsOneWidget);

      await t.tap(dialogButton('Cancel'));
      await settle(t);
      expect(repo.calls, isEmpty, reason: 'Cancel must not remove anything');
      expect(find.text('Fake Stadium'), findsOneWidget);

      await t.tap(find.text('Remove'));
      await settle(t);
      await t.tap(dialogButton('Remove'));
      await settle(t);
      expect(repo.calls, [('r1', 'remove', null)]);
      expect(find.text('Fake Stadium'), findsNothing);
      expect(find.text('Removed'), findsOneWidget);
    });

    testWidgets('a venue on a match is cleared, not the match', (t) async {
      final repo = RecordingRepo([
        venue(requestId: null, matchId: 'm1', status: 'confirmed'),
      ]);
      await show(t, repo);
      await t.tap(find.text('Remove'));
      await settle(t);
      expect(find.textContaining('cleared from the match'), findsOneWidget);
      expect(find.textContaining('will be deleted'), findsNothing);
    });

    testWidgets('a request that already became a match is cleared too',
        (t) async {
      final repo = RecordingRepo([venue(status: 'pending')]);
      await show(t, repo);
      await t.tap(find.text('Remove'));
      await settle(t);
      expect(find.textContaining('cleared from the match'), findsOneWidget);
    });

    testWidgets(
        'a venue suggested on a proposal cancels the proposal, not the request',
        (t) async {
      final repo = RecordingRepo([
        venue(
          id: 's1',
          text: 'Beach Arena',
          requestId: null,
          proposalId: 'p1',
          target: 'Anorthosis',
        ),
      ]);
      await show(t, repo);

      await t.tap(find.text('Remove'));
      await settle(t);
      expect(find.text('Remove this venue?'), findsOneWidget);
      expect(find.textContaining('suggested in a match proposal'),
          findsOneWidget);
      expect(find.textContaining('cancelled'), findsOneWidget);
      expect(find.textContaining('stays open'), findsOneWidget);
      // None of the other outcomes may be promised.
      expect(find.textContaining('will be deleted'), findsNothing);
      expect(find.textContaining('cleared from the match'), findsNothing);

      await t.tap(dialogButton('Remove'));
      await settle(t);
      expect(repo.calls, [('s1', 'remove', null)]);
      expect(find.text('Beach Arena'), findsNothing);
      expect(find.text('Removed'), findsOneWidget);
    });

    testWidgets('a reported suggestion on an already full request reads the same',
        (t) async {
      final repo = RecordingRepo([
        venue(
          id: 's2',
          requestId: null,
          proposalId: 'p2',
          target: 'Anorthosis',
          reason: 'reported',
          reports: 2,
          status: 'confirmed',
        ),
      ]);
      await show(t, repo);
      await t.tap(find.text('Remove'));
      await settle(t);
      expect(find.textContaining('suggested in a match proposal'),
          findsOneWidget);
      expect(find.textContaining('will be deleted'), findsNothing);
    });

    testWidgets('a suggestion that became the match venue is cleared from it',
        (t) async {
      final repo = RecordingRepo([
        venue(
          id: 's3',
          requestId: 'q1',
          matchId: 'm1',
          proposalId: 'p3',
          target: 'Anorthosis',
          status: 'pending',
        ),
      ]);
      await show(t, repo);
      await t.tap(find.text('Remove'));
      await settle(t);
      expect(find.textContaining('cleared from the match'), findsOneWidget);
      expect(find.textContaining('cancelled'), findsNothing);
      expect(find.textContaining('will be deleted'), findsNothing);
    });

    testWidgets('tapping outside the dialog does nothing', (t) async {
      final repo = RecordingRepo([venue()]);
      await show(t, repo);
      await t.tap(find.text('Remove'));
      await settle(t);
      await t.tapAt(const Offset(4, 4));
      await settle(t);
      expect(find.text('Remove this venue?'), findsNothing);
      expect(repo.calls, isEmpty);
    });
  });

  group('Link to court', () {
    testWidgets("the server's closest court is preselected", (t) async {
      final repo = RecordingRepo([
        venue(
          text: 'Kick on 5',
          reason: 'other_city',
          suggestedId: 'c2',
          suggestedName: 'Kick On Fives',
          suggestedCity: 'Paphos',
          score: 0.62,
        ),
      ]);
      await show(t, repo);
      expect(find.textContaining('Closest court: Kick On Fives (Paphos)'),
          findsOneWidget);
      expect(find.textContaining('62% similar'), findsOneWidget);

      await t.tap(find.text('Link to court'));
      await settle(t);
      expect(find.text('Players typed: "Kick on 5"'), findsOneWidget);
      expect(find.textContaining('never see this link'), findsOneWidget);

      await t.tap(find.widgetWithText(FilledButton, 'Link'));
      await settle(t);
      expect(repo.calls, [('r1', 'link', 'c2')]);
      expect(find.text('Linked to the court'), findsOneWidget);
      expect(find.text('Kick on 5'), findsNothing);
    });

    testWidgets('without a suggestion Link stays disabled until one is picked',
        (t) async {
      final repo = RecordingRepo([venue(text: 'Joe garden')]);
      await show(t, repo);
      await t.tap(find.text('Link to court'));
      await settle(t);

      FilledButton linkButton() =>
          t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Link'));
      expect(linkButton().onPressed, isNull);

      // Courts of the request's own city (Paphos) are listed first.
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await settle(t);
      final entries = t
          .widgetList<Text>(find.textContaining(' · '))
          .map((w) => w.data)
          .whereType<String>()
          .where((s) => courts.any((c) => s.startsWith(c.name)))
          .toList();
      expect(entries.first, startsWith('Kick On Fives'));

      await t.tap(find.text('Wembley · Limassol').last);
      await settle(t);
      expect(linkButton().onPressed, isNotNull);

      await t.tap(find.widgetWithText(FilledButton, 'Link'));
      await settle(t);
      expect(repo.calls, [('r1', 'link', 'c3')]);
    });

    testWidgets('cancelling the picker sends nothing', (t) async {
      final repo = RecordingRepo([venue()]);
      await show(t, repo);
      await t.tap(find.text('Link to court'));
      await settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(t);
      expect(repo.calls, isEmpty);
      expect(find.text('Seaside Pitch'), findsOneWidget);
    });
  });

  group('loading and failing', () {
    testWidgets('a failed load offers Try again, which recovers', (t) async {
      final repo = RecordingRepo([venue()])..fetchError = Exception('boom');
      await show(t, repo);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Seaside Pitch'), findsNothing);

      repo.fetchError = null;
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Seaside Pitch'), findsOneWidget);
    });

    testWidgets('an empty list says everything looks fine', (t) async {
      await show(t, RecordingRepo([]));
      expect(find.textContaining('Nothing to review'), findsOneWidget);
    });

    testWidgets('the refresh button reloads the list', (t) async {
      final repo = RecordingRepo([venue()]);
      await show(t, repo);
      final before = repo.fetches;
      repo.items.add(venue(id: 'r2', text: 'Second Venue'));
      await t.tap(find.byTooltip('Refresh'));
      await settle(t);
      expect(repo.fetches, greaterThan(before));
      expect(find.text('Second Venue'), findsOneWidget);
    });
  });

  group('cards read well', () {
    testWidgets('reason chips, counts and context for each kind', (t) async {
      final repo = RecordingRepo([
        venue(id: 'a', text: 'Nowhere Park', reason: 'no_match'),
        venue(id: 'b', text: 'Far Away', reason: 'other_city'),
        venue(
          id: 'c',
          text: 'Rude Name',
          reason: 'reported',
          reports: 3,
          requestId: null,
          matchId: 'm9',
          status: 'confirmed',
        ),
      ]);
      await show(t, repo, height: 3000);
      expect(find.text('No court match'), findsOneWidget);
      expect(find.text('Matches a court in another city'), findsOneWidget);
      expect(find.text('Reported by 3 players'), findsOneWidget);
      expect(find.textContaining('confirmed match'), findsOneWidget);
      expect(find.textContaining('request searching'), findsNWidgets(2));
      expect(find.textContaining('Keravnos FC · captain Andreas'),
          findsNWidgets(3));
    });

    testWidgets('a suggested venue says who it was suggested to', (t) async {
      final repo = RecordingRepo([
        venue(
          id: 's',
          text: 'Beach Arena',
          requestId: null,
          proposalId: 'p1',
          target: 'Anorthosis',
        ),
        venue(id: 'n', text: 'Plain Request Venue'),
      ]);
      await show(t, repo, height: 3000);
      expect(find.textContaining('suggested to Anorthosis'), findsOneWidget);
      // The author of a suggestion is not necessarily a captain.
      expect(find.textContaining('Keravnos FC · proposed by Andreas'),
          findsOneWidget);
      expect(find.textContaining('Keravnos FC · captain Andreas'),
          findsOneWidget);
      expect(find.textContaining('suggested in a proposal'), findsNothing);
    });

    testWidgets('a suggestion without the receiving team name still reads well',
        (t) async {
      final repo = RecordingRepo([
        venue(requestId: null, proposalId: 'p1', target: null),
        venue(id: 'e', requestId: null, proposalId: 'p2', target: ''),
      ]);
      await show(t, repo, height: 3000);
      expect(find.textContaining('suggested in a proposal'), findsNWidgets(2));
      expect(find.textContaining('suggested to'), findsNothing);
    });

    testWidgets('the page tells the admin suggestions are listed here too',
        (t) async {
      await show(t, RecordingRepo([]));
      expect(find.textContaining('suggested in match proposals'),
          findsOneWidget);
    });

    testWidgets('missing optional fields do not break a card', (t) async {
      final repo = RecordingRepo([
        FlaggedVenueModel(
          reviewId: 'x',
          venueText: 'Bare Venue',
          reason: 'something_new',
          createdAt: DateTime.utc(2026, 10, 30),
        ),
      ]);
      await show(t, repo);
      expect(find.text('Bare Venue'), findsOneWidget);
      expect(find.text('Needs review'), findsOneWidget);
    });
  });

  group('phones and awkward text', () {
    final awkward = [
      venue(
        id: 'g',
        text: 'Γήπεδο Ποδοσφαίρου Μεγάλης Αθλητικής Εγκατάστασης Πάφου 🏟️⚽',
        team: 'Αθλητικός Όμιλος Κεραυνός Στροβόλου Νέοι',
        captain: 'Ανδρέας Παπαδόπουλος-Χαραλαμπίδης',
      ),
      venue(id: 'w', text: 'W' * 60, reason: 'reported', reports: 12),
      venue(id: 'e', text: '⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅', reason: 'other_city'),
      venue(
        id: 'h',
        text: 'مرمى ملعب كرة القدم الكبير',
        suggestedId: 'c3',
        suggestedName: 'Wembley Mini Football Center (Ypsonas Industrial Area)',
        suggestedCity: 'Limassol',
        score: 0.55,
      ),
    ];

    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 390.0]) {
        testWidgets(
            'a long suggestion and its dialog at width $width, '
            'text ${(scale * 100).round()}%', (t) async {
          final repo = RecordingRepo([
            venue(
              id: 'sg',
              text: 'Γήπεδο Αγίου Γεωργίου Μεγάλη Αθλητική Εγκατάσταση 🏟️',
              requestId: null,
              proposalId: 'p9',
              target: 'Ομόνοια Λευκωσίας Παλαίμαχοι Βετεράνοι Ομάδα Α',
              team: 'Αθλητικός Όμιλος Κεραυνός Στροβόλου Νέοι',
              captain: 'Ανδρέας Παπαδόπουλος-Χαραλαμπίδης',
              reason: 'reported',
              reports: 12,
            ),
          ]);
          await show(t, repo, width: width, height: 3000, textScale: scale);
          expect(find.textContaining('suggested to'), findsOneWidget);
          await t.tap(find.text('Remove').first, warnIfMissed: false);
          await settle(t);
          expect(find.text('Remove this venue?'), findsOneWidget);
          expect(find.textContaining('cancelled'), findsOneWidget);
        });
      }
    }

    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 390.0, 768.0]) {
        testWidgets('width $width, text ${(scale * 100).round()}%', (t) async {
          await show(t, RecordingRepo(List.of(awkward)),
              width: width, height: 3000, textScale: scale);
          expect(find.byType(AdminFlaggedPage), findsOneWidget);
          // Any RenderFlex overflow would already have failed the test.
          await t.tap(find.text('Remove').first, warnIfMissed: false);
          await settle(t);
        });

        testWidgets('link dialog at width $width, text ${(scale * 100).round()}%',
            (t) async {
          await show(t, RecordingRepo(List.of(awkward)),
              width: width, height: 3000, textScale: scale);
          await t.tap(find.text('Link to court').first, warnIfMissed: false);
          await settle(t);
          expect(find.text('Link to a court'), findsOneWidget);
          // The long suggested court is preselected; open the picker as well.
          await t.tap(find.byType(DropdownButtonFormField<String>),
              warnIfMissed: false);
          await settle(t);
        });
      }
    }
  });
}

