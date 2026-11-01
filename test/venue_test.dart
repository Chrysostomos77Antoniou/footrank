import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/admin/models/flagged_venue_model.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/match/presentation/widgets/venue_widgets.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('cleanVenueInput', () {
    test('trims and collapses whitespace but keeps the captain\'s casing', () {
      expect(cleanVenueInput('  Wembley   Mini\tFootball \n'),
          'Wembley Mini Football');
      expect(cleanVenueInput('lower case venue'), 'lower case venue');
    });
  });

  group('validateVenueInput', () {
    test('requires something', () {
      expect(validateVenueInput(null), isNotNull);
      expect(validateVenueInput(''), isNotNull);
      expect(validateVenueInput('    '), isNotNull);
    });

    test('accepts ordinary names in Latin and Greek', () {
      expect(validateVenueInput('Pafos Arena'), isNull);
      expect(validateVenueInput('Γήπεδο Κέντρο'), isNull);
      expect(validateVenueInput('5v5 Park'), isNull);
    });

    test('rejects names with fewer than two letters', () {
      expect(validateVenueInput('a'), isNotNull);
      expect(validateVenueInput('12'), isNotNull);
      expect(validateVenueInput('A1'), isNotNull);
    });

    test('enforces the 60-character limit', () {
      expect(validateVenueInput('a' * 60), isNull);
      expect(validateVenueInput('a' * 61), isNotNull);
    });
  });

  group('validateOptionalVenueInput', () {
    test('an empty field is fine -- it means "no suggestion"', () {
      expect(validateOptionalVenueInput(null), isNull);
      expect(validateOptionalVenueInput(''), isNull);
      expect(validateOptionalVenueInput('   \n\t '), isNull);
    });

    test('anything typed must still be a believable name', () {
      expect(validateOptionalVenueInput('Pafos Arena'), isNull);
      expect(validateOptionalVenueInput('Γήπεδο Κέντρο'), isNull);
      expect(validateOptionalVenueInput('a'), isNotNull);
      expect(validateOptionalVenueInput('12'), isNotNull);
      expect(validateOptionalVenueInput('a' * 61), isNotNull);
    });
  });

  group('MatchProposalModel venue', () {
    Map<String, dynamic> row({String? venue, Map<String, dynamic>? request}) => {
          'id': 'p1',
          'request_id': 'r1',
          'proposing_team_id': 't1',
          'proposing_user_id': 'u1',
          'status': 'pending',
          'created_at': '2026-10-30T10:00:00Z',
          'venue_text': venue,
          if (request != null) 'match_requests': request,
        };

    test('keeps the suggested venue exactly as stored', () {
      final p = MatchProposalModel.fromJson(row(venue: 'Seaside Pitch'));
      expect(p.venueText, 'Seaside Pitch');
      expect(p.hasVenueSuggestion, isTrue);
    });

    test('no suggestion when the column is null, empty or missing', () {
      expect(MatchProposalModel.fromJson(row()).hasVenueSuggestion, isFalse);
      expect(MatchProposalModel.fromJson(row(venue: '')).hasVenueSuggestion,
          isFalse);
      final old = row()..remove('venue_text');
      final p = MatchProposalModel.fromJson(old);
      expect(p.venueText, isNull);
      expect(p.hasVenueSuggestion, isFalse);
    });

    test('reads the venue of the request it was sent to', () {
      final p = MatchProposalModel.fromJson(row(
        venue: 'Mine',
        request: {
          'city': 'Larnaca',
          'scheduled_at': '2026-11-02T16:00:00Z',
          'match_type': 'casual',
          'format': '5v5',
          'venue_text': 'Theirs',
          'teams': {'name': 'Anorthosis', 'rating': 1500, 'logo_url': null},
        },
      ));
      expect(p.venueText, 'Mine');
      expect(p.requestVenueText, 'Theirs');
      expect(p.targetTeamName, 'Anorthosis');
    });
  });

  group('venueText parsing', () {
    test('MatchRequestModel keeps the venue exactly as typed', () {
      final r = MatchRequestModel.fromJson({
        'id': 'r1',
        'team_id': 't1',
        'captain_id': 'c1',
        'city': 'Nicosia',
        'scheduled_at': '2026-11-02T18:00:00Z',
        'match_type': 'casual',
        'format': '5v5',
        'status': 'searching',
        'created_at': '2026-10-30T10:00:00Z',
        'venue_text': 'my local pitch',
      });
      expect(r.venueText, 'my local pitch');
    });

    test('older rows without a venue still parse', () {
      final r = MatchRequestModel.fromJson({
        'id': 'r1',
        'team_id': 't1',
        'captain_id': 'c1',
        'city': 'Nicosia',
        'scheduled_at': '2026-11-02T18:00:00Z',
        'match_type': 'casual',
        'format': '5v5',
        'status': 'searching',
        'created_at': '2026-10-30T10:00:00Z',
      });
      expect(r.venueText, isNull);
    });

    test('MatchModel parses the venue and ignores legacy court columns', () {
      final m = MatchModel.fromJson({
        'id': 'm1',
        'home_team_id': 'h',
        'away_team_id': 'a',
        'city': 'Limassol',
        'scheduled_at': '2026-11-02T18:00:00Z',
        'match_type': 'ranked',
        'format': '5v5',
        'status': 'confirmed',
        'created_at': '2026-10-30T10:00:00Z',
        'venue_text': 'Seaside Pitch',
        // Rows from before the change may still carry a court id; the model
        // must not surface it.
        'suggested_court_id': 'c1',
        'suggested_court': {'name': 'Some Court', 'address': 'x'},
      });
      expect(m.venueText, 'Seaside Pitch');
    });
  });

  group('FlaggedVenueModel', () {
    Map<String, dynamic> row({String reason = 'no_match', int reports = 0}) => {
          'review_id': 'v1',
          'request_id': 'r1',
          'match_id': null,
          'venue_text': 'Some Venue',
          'reason': reason,
          'city': 'Paphos',
          'scheduled_at': '2026-11-02T18:00:00Z',
          'team_name': 'Keravnos FC',
          'captain_name': 'Andreas',
          'request_status': 'searching',
          'report_count': reports,
          'suggested_court_id': null,
          'suggested_court_name': null,
          'suggested_court_city': null,
          'match_score': 0.4321,
          'created_at': '2026-10-30T10:00:00Z',
        };

    test('parses an admin_list_flagged_venues row', () {
      final v = FlaggedVenueModel.fromJson(row());
      expect(v.venueText, 'Some Venue');
      expect(v.matchScore, closeTo(0.4321, 1e-9));
      expect(v.suggestedCourtName, isNull);
      expect(v.matchId, isNull);
      expect(v.isReported, isFalse);
    });

    test('labels each reason for the admin', () {
      expect(FlaggedVenueModel.fromJson(row()).reasonLabel, 'No court match');
      expect(FlaggedVenueModel.fromJson(row(reason: 'other_city')).reasonLabel,
          contains('another city'));
      expect(
          FlaggedVenueModel.fromJson(row(reason: 'reported', reports: 1))
              .reasonLabel,
          'Reported');
      expect(
          FlaggedVenueModel.fromJson(row(reason: 'reported', reports: 3))
              .reasonLabel,
          'Reported by 3 players');
    });

    test('an integer score from the server still parses', () {
      final r = row()..['match_score'] = 1;
      expect(FlaggedVenueModel.fromJson(r).matchScore, 1.0);
    });

    test('a venue typed on a request is not a suggestion', () {
      final v = FlaggedVenueModel.fromJson(row());
      expect(v.proposalId, isNull);
      expect(v.targetTeamName, isNull);
      expect(v.isSuggestion, isFalse);
    });

    test('a venue suggested on a proposal says so and who received it', () {
      final r = row()
        ..['request_id'] = null
        ..['proposal_id'] = 'p1'
        ..['target_team_name'] = 'Anorthosis';
      final v = FlaggedVenueModel.fromJson(r);
      expect(v.isSuggestion, isTrue);
      expect(v.proposalId, 'p1');
      expect(v.requestId, isNull);
      expect(v.targetTeamName, 'Anorthosis');
      expect(v.teamName, 'Keravnos FC');
    });

    test('an accepted suggestion keeps its proposal next to the match', () {
      final r = row()
        ..['match_id'] = 'm1'
        ..['proposal_id'] = 'p1';
      final v = FlaggedVenueModel.fromJson(r);
      expect(v.isSuggestion, isTrue);
      expect(v.matchId, 'm1');
      expect(v.requestId, 'r1');
    });
  });

  group('venue UI', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        );

    Future<void> narrow(WidgetTester t) async {
      t.view.physicalSize = const Size(320 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }

    testWidgets('requesting captain can change the venue and call', (t) async {
      await narrow(t);
      var edits = 0, calls = 0;
      await t.pumpWidget(host(VenueCard(
        venueText: 'Seaside Pitch',
        isRequester: true,
        canEdit: true,
        canReport: false,
        callLabel: 'Call Andreas',
        onCall: () => calls++,
        onEdit: () => edits++,
        onDirections: () {},
      )));
      expect(find.text('Seaside Pitch'), findsOneWidget);
      expect(find.text('Get Directions'), findsOneWidget);
      expect(find.text('Change venue'), findsOneWidget);
      expect(find.byTooltip('Report venue name'), findsNothing);
      expect(find.text(kVenueDisclaimer), findsOneWidget);

      await t.tap(find.text('Change venue'));
      await t.tap(find.text('Call Andreas'));
      expect(edits, 1);
      expect(calls, 1);
    });

    testWidgets('the other captain can report and call, not edit', (t) async {
      await narrow(t);
      var reports = 0;
      await t.pumpWidget(host(VenueCard(
        venueText: 'Seaside Pitch',
        isRequester: false,
        canEdit: false,
        canReport: true,
        callLabel: 'Call Nikos',
        onCall: () {},
        onReport: () => reports++,
        onDirections: () {},
      )));
      expect(find.text('Change venue'), findsNothing);
      expect(find.text('Call Nikos'), findsOneWidget);
      await t.tap(find.byTooltip('Report venue name'));
      expect(reports, 1);
    });

    testWidgets('an unset venue says so and offers nothing to report',
        (t) async {
      await narrow(t);
      await t.pumpWidget(host(const VenueCard(
        venueText: null,
        isRequester: false,
        canEdit: false,
        canReport: true,
      )));
      expect(find.text('Not set yet'), findsOneWidget);
      expect(find.text('Get Directions'), findsNothing);
      expect(find.byTooltip('Report venue name'), findsNothing);
    });

    testWidgets('a very long venue name wraps without overflowing', (t) async {
      await narrow(t);
      await t.pumpWidget(host(VenueCard(
        venueText: 'A' * 60,
        isRequester: true,
        canEdit: true,
        canReport: false,
        callLabel: 'Call someone with a rather long name indeed',
        onCall: () {},
        onEdit: () {},
        onDirections: () {},
      )));
      expect(find.byType(VenueCard), findsOneWidget);
    });

    testWidgets('the preview shows exactly what was typed', (t) async {
      await narrow(t);
      await t.pumpWidget(host(const VenuePreviewCard(
        venueText: '  My   Local  Pitch ',
        whenLabel: '30/10/2026 · 19:00 · Nicosia',
      )));
      expect(find.text('My Local Pitch'), findsOneWidget);
      expect(find.text('30/10/2026 · 19:00 · Nicosia'), findsOneWidget);
      expect(find.text(kVenueDisclaimer), findsOneWidget);
    });

    testWidgets('the preview shows a placeholder until something is typed',
        (t) async {
      await narrow(t);
      await t.pumpWidget(host(const VenuePreviewCard(
        venueText: '   ',
        whenLabel: 'x',
      )));
      expect(find.text('Your venue name'), findsOneWidget);
    });

    testWidgets('the change-venue dialog validates and returns clean text',
        (t) async {
      String? result = 'unset';
      await t.pumpWidget(host(Builder(
        builder: (ctx) => TextButton(
          onPressed: () async =>
              result = await showEditVenueDialog(ctx, initial: 'Old Venue'),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Change venue'), findsOneWidget);

      await t.enterText(find.byType(TextFormField), '   ');
      await t.tap(find.text('Save'));
      await t.pump();
      expect(find.text('Enter where you will play'), findsOneWidget);
      expect(result, 'unset');

      await t.enterText(find.byType(TextFormField), '  New   Venue ');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(result, 'New Venue');
    });

    testWidgets('cancelling the dialog returns null', (t) async {
      String? result = 'unset';
      await t.pumpWidget(host(Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await showEditVenueDialog(ctx),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('venue UI under stress', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final names = <String>[
      'A' * 60,
      'Γήπεδο Ποδοσφαίρου Μεγάλης Αθλητικής Εγκατάστασης Πάφου ⚽🏟️',
      '⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅',
      'ملعب كرة القدم الكبير للأحياء',
      'Wembley',
    ];

    Widget app(Widget child, double scale) => MaterialApp(
          theme: AppTheme.dark,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: c!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        );

    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 390.0]) {
        testWidgets(
            'cards hold any name at width $width, text ${(scale * 100).round()}%',
            (t) async {
          t.view.physicalSize = Size(width * 2, 1600);
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          for (final name in names) {
            await t.pumpWidget(app(
              Column(children: [
                VenueCard(
                  venueText: name,
                  isRequester: true,
                  canEdit: true,
                  canReport: true,
                  callLabel: 'Call Ανδρέας Παπαδόπουλος-Χαραλαμπίδης',
                  onCall: () {},
                  onEdit: () {},
                  onReport: () {},
                  onDirections: () {},
                ),
                VenuePreviewCard(venueText: name, whenLabel: '30/10/2026 · 19:00 · Nicosia'),
              ]),
              scale,
            ));
            await t.pump(const Duration(milliseconds: 300));
            // An overflow anywhere would already have failed the test.
            expect(find.byType(VenueCard), findsOneWidget);
          }
        });
      }
    }

    testWidgets('the change-venue dialog survives a small screen and big text',
        (t) async {
      t.view.physicalSize = const Size(320 * 2, 568 * 2);
      t.view.devicePixelRatio = 2;
      // The on-screen keyboard takes roughly half the screen.
      t.view.viewInsets = const FakeViewPadding(bottom: 600);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      await t.pumpWidget(app(
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showEditVenueDialog(ctx, initial: names[1]),
            child: const Text('open'),
          ),
        ),
        2.0,
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
      await t.enterText(find.byType(TextFormField), names[2]);
      await t.pump();
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'the accept dialog holds any venue at 320 px, text ${(scale * 100).round()}%',
          (t) async {
        t.view.physicalSize = const Size(320 * 2, 568 * 2);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        for (final name in names) {
          await t.pumpWidget(app(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showAcceptProposalDialog(
                  ctx,
                  teamName: 'Ομόνοια Λευκωσίας Παλαίμαχοι Βετεράνοι Ομάδα Α',
                  venueText: name,
                ),
                child: const Text('open'),
              ),
            ),
            scale,
          ));
          await t.tap(find.text('open'));
          await t.pumpAndSettle();
          // An overflow anywhere would already have failed the test, and the
          // buttons must stay reachable however long the name is.
          expect(find.text('Accept this proposal?'), findsOneWidget);
          await t.ensureVisible(find.text('Accept'));
          await t.tap(find.text('Cancel'));
          await t.pumpAndSettle();
        }
      });
    }

    for (final scale in [1.0, 2.0]) {
      for (final keyboard in [false, true]) {
        testWidgets(
            'the propose dialog holds any venue at 320 px, text '
            '${(scale * 100).round()}%, keyboard ${keyboard ? 'open' : 'closed'}',
            (t) async {
          t.view.physicalSize = const Size(320 * 2, 568 * 2);
          t.view.devicePixelRatio = 2;
          if (keyboard) t.view.viewInsets = const FakeViewPadding(bottom: 500);
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.view.resetViewInsets);
          for (final name in names) {
            await t.pumpWidget(app(
              Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showProposeDialog(
                    ctx,
                    opponentName: 'Ομόνοια Λευκωσίας Παλαίμαχοι Βετεράνοι',
                    city: 'Λευκωσία',
                    requestVenue: name,
                  ),
                  child: const Text('open'),
                ),
              ),
              scale,
            ));
            await t.tap(find.text('open'));
            await t.pumpAndSettle();
            await t.enterText(find.byType(TextFormField), name);
            await t.pump();
            // Whatever the screen, the dialog is there and can be dismissed:
            // an overflow anywhere would already have failed the test.
            expect(find.text('Propose this match?'), findsOneWidget);
            await t.tap(find.text('Cancel'));
            await t.pumpAndSettle();
          }
        });
      }
    }
  });

  group('propose dialog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // The dialog resolves to a ProposeChoice, or null when cancelled.
    ProposeChoice? choice;
    var closed = false;

    Future<void> open(WidgetTester t, {String? requestVenue}) async {
      choice = null;
      closed = false;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  choice = await showProposeDialog(
                    ctx,
                    opponentName: 'Anorthosis',
                    city: 'Larnaca',
                    requestVenue: requestVenue,
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('sending without typing a venue plays at the request\'s venue',
        (t) async {
      await open(t, requestVenue: 'Their Ground');
      expect(find.text('Propose this match?'), findsOneWidget);
      expect(find.textContaining('against Anorthosis in Larnaca'),
          findsOneWidget);
      await t.tap(find.text('Send Proposal'));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(choice, isNotNull);
      expect(choice!.venueText, isNull);
    });

    testWidgets('a typed venue comes back cleaned', (t) async {
      await open(t, requestVenue: 'Their Ground');
      await t.enterText(find.byType(TextFormField), '  Seaside   Pitch ');
      await t.tap(find.text('Send Proposal'));
      await t.pumpAndSettle();
      expect(choice!.venueText, 'Seaside Pitch');
    });

    testWidgets('the keyboard "done" key sends it as well', (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField), 'Beach Arena');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(choice!.venueText, 'Beach Arena');
    });

    testWidgets('Greek and emoji names are kept as typed', (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField), 'Γήπεδο Κέντρο ⚽');
      await t.tap(find.text('Send Proposal'));
      await t.pumpAndSettle();
      expect(choice!.venueText, 'Γήπεδο Κέντρο ⚽');
    });

    testWidgets('a one-letter venue is refused and the dialog stays open',
        (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField), 'a');
      await t.tap(find.text('Send Proposal'));
      await t.pump();
      expect(find.text('Use 2–60 characters'), findsOneWidget);
      expect(closed, isFalse);
      expect(find.text('Propose this match?'), findsOneWidget);

      // Correcting it lets the proposal through.
      await t.enterText(find.byType(TextFormField), 'Arena');
      await t.tap(find.text('Send Proposal'));
      await t.pumpAndSettle();
      expect(choice!.venueText, 'Arena');
    });

    testWidgets('digits alone are not a venue name', (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField), '12345');
      await t.tap(find.text('Send Proposal'));
      await t.pump();
      expect(find.text("Enter the venue's name"), findsOneWidget);
      expect(closed, isFalse);
    });

    testWidgets('spaces only count as no venue', (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField), '     ');
      await t.tap(find.text('Send Proposal'));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(choice!.venueText, isNull);
    });

    testWidgets('the field stops at 60 characters', (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField), 'A' * 90);
      await t.tap(find.text('Send Proposal'));
      await t.pumpAndSettle();
      expect(choice!.venueText, 'A' * 60);
    });

    testWidgets('Cancel sends nothing', (t) async {
      await open(t, requestVenue: 'Their Ground');
      await t.enterText(find.byType(TextFormField), 'Seaside Pitch');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(choice, isNull);
    });

    testWidgets('shows their venue and explains accept / decline', (t) async {
      await open(t, requestVenue: 'Their Ground');
      expect(find.text('Their venue: Their Ground'), findsOneWidget);
      expect(find.text('Prefer a different venue? (optional)'), findsOneWidget);
      expect(find.textContaining('Leave it empty to play at their venue'),
          findsOneWidget);
      expect(find.text(kVenueDisclaimer), findsOneWidget);
    });

    testWidgets('an older request with no venue just asks where to play',
        (t) async {
      await open(t);
      expect(find.textContaining('Their venue'), findsNothing);
      expect(find.text('Where would you like to play? (optional)'),
          findsOneWidget);
      expect(find.textContaining('accept your venue or decline'),
          findsOneWidget);
    });

    testWidgets('an empty request venue is treated as none', (t) async {
      await open(t, requestVenue: '');
      expect(find.textContaining('Their venue'), findsNothing);
      expect(find.text('Where would you like to play? (optional)'),
          findsOneWidget);
    });
  });

  group('accept dialog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    bool? answer;
    var closed = false;

    Future<void> open(WidgetTester t, {String? venue, String team = 'Keravnos FC'}) async {
      answer = null;
      closed = false;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  answer = await showAcceptProposalDialog(
                    ctx,
                    teamName: team,
                    venueText: venue,
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('a proposal without a venue is the plain confirmation',
        (t) async {
      await open(t);
      expect(find.text('Accept this proposal?'), findsOneWidget);
      expect(find.textContaining('Keravnos FC wants to play your match'),
          findsOneWidget);
      expect(find.textContaining('Venue:'), findsNothing);
      expect(find.text(kVenueDisclaimer), findsNothing);
    });

    testWidgets('an empty or blank venue counts as none', (t) async {
      await open(t, venue: '   ');
      expect(find.textContaining('Venue:'), findsNothing);
    });

    testWidgets('a suggested venue is shown with what accepting means',
        (t) async {
      await open(t, venue: '  Seaside   Pitch ');
      expect(find.text('Venue: Seaside Pitch'), findsOneWidget);
      expect(find.textContaining('The match will be played here'),
          findsOneWidget);
      expect(find.textContaining('Decline instead'), findsOneWidget);
      expect(find.text(kVenueDisclaimer), findsOneWidget);
    });

    testWidgets('Accept answers true', (t) async {
      await open(t, venue: 'Seaside Pitch');
      await t.tap(find.text('Accept'));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(answer, isTrue);
    });

    testWidgets('Cancel answers false', (t) async {
      await open(t, venue: 'Seaside Pitch');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(answer, isFalse);
    });

    testWidgets('tapping outside the dialog never accepts', (t) async {
      await open(t, venue: 'Seaside Pitch');
      await t.tapAt(const Offset(4, 4));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(answer, isNot(true));
    });
  });

  group('report flow', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget host(void Function(BuildContext) onTap) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () => onTap(ctx),
                  child: const Text('flag'),
                ),
              ),
            ),
          ),
        );

    testWidgets('Cancel sends nothing', (t) async {
      var sent = 0;
      await t.pumpWidget(host((ctx) => reportVenueFlow(ctx,
          requestId: 'r1',
          report: ({requestId, matchId, proposalId}) async => sent++)));
      await t.tap(find.text('flag'));
      await t.pumpAndSettle();
      expect(find.text('Report this venue name?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(sent, 0);
      expect(find.text("Thanks, we'll review it"), findsNothing);
    });

    testWidgets('reporting a request sends only the request id', (t) async {
      final calls = <(String?, String?)>[];
      await t.pumpWidget(host((ctx) => reportVenueFlow(ctx,
          requestId: 'r1',
          report: ({requestId, matchId, proposalId}) async =>
              calls.add((requestId, matchId)))));
      await t.tap(find.text('flag'));
      await t.pumpAndSettle();
      await t.tap(find.text('Report'));
      await t.pumpAndSettle();
      expect(calls, [('r1', null)]);
      expect(find.text("Thanks, we'll review it"), findsOneWidget);
    });

    testWidgets('reporting a suggested venue sends only the proposal id',
        (t) async {
      final calls = <(String?, String?, String?)>[];
      await t.pumpWidget(host((ctx) => reportVenueFlow(ctx,
          proposalId: 'p1',
          report: ({requestId, matchId, proposalId}) async =>
              calls.add((requestId, matchId, proposalId)))));
      await t.tap(find.text('flag'));
      await t.pumpAndSettle();
      await t.tap(find.text('Report'));
      await t.pumpAndSettle();
      expect(calls, [(null, null, 'p1')]);
      expect(find.text("Thanks, we'll review it"), findsOneWidget);
    });

    testWidgets('a refused report of a suggestion is explained', (t) async {
      await t.pumpWidget(host((ctx) => reportVenueFlow(ctx,
          proposalId: 'p1',
          report: ({requestId, matchId, proposalId}) async =>
              throw const PostgrestException(
                message: 'Only the captain who received the proposal can '
                    'report its venue',
                code: 'P0001',
              ))));
      await t.tap(find.text('flag'));
      await t.pumpAndSettle();
      await t.tap(find.text('Report'));
      await t.pumpAndSettle();
      expect(
        find.text('Only the captain who received the proposal can report '
            'its venue'),
        findsOneWidget,
      );
      expect(find.text("Thanks, we'll review it"), findsNothing);
    });

    testWidgets('reporting a match sends only the match id', (t) async {
      final calls = <(String?, String?)>[];
      await t.pumpWidget(host((ctx) => reportVenueFlow(ctx,
          matchId: 'm1',
          report: ({requestId, matchId, proposalId}) async =>
              calls.add((requestId, matchId)))));
      await t.tap(find.text('flag'));
      await t.pumpAndSettle();
      await t.tap(find.text('Report'));
      await t.pumpAndSettle();
      expect(calls, [(null, 'm1')]);
    });

    testWidgets('a server refusal is explained in plain words', (t) async {
      await t.pumpWidget(host((ctx) => reportVenueFlow(ctx,
          matchId: 'm1',
          report: ({requestId, matchId, proposalId}) async => throw const PostgrestException(
                message: 'You cannot report your own venue',
                code: 'P0001',
              ))));
      await t.tap(find.text('flag'));
      await t.pumpAndSettle();
      await t.tap(find.text('Report'));
      await t.pumpAndSettle();
      expect(find.text('You cannot report your own venue'), findsOneWidget);
      expect(find.textContaining('code:'), findsNothing);
      expect(find.text("Thanks, we'll review it"), findsNothing);
    });

    testWidgets('hitting the report rate limit asks the user to slow down',
        (t) async {
      await t.pumpWidget(host((ctx) => reportVenueFlow(ctx,
          requestId: 'r1',
          report: ({requestId, matchId, proposalId}) async => throw const PostgrestException(
                message: 'rate_limited: too many reports, try again later',
                code: 'P0001',
              ))));
      await t.tap(find.text('flag'));
      await t.pumpAndSettle();
      await t.tap(find.text('Report'));
      await t.pumpAndSettle();
      expect(find.textContaining('too often'), findsOneWidget);
    });
  });
}
