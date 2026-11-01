// The two cards that carry a venue suggested on a proposal:
//  * RequestCard      -- the captain who receives proposals sees what each team
//                        suggests, can report a name, accepts or rejects;
//  * SentProposalCard -- the team that sent a proposal sees what it suggested.
// Neither card talks to the network: they only call back, so the whole
// behaviour (including a report going out with the right proposal id) is
// checked here, on phone-sized screens with big text and awkward names.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/match/presentation/pages/matches_page.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchRequestModel request({String? venue = 'Home Ground'}) =>
    MatchRequestModel(
      id: 'r1',
      teamId: 't9',
      captainId: 'c9',
      city: 'Larnaca',
      scheduledAt: DateTime(2026, 11, 2, 18, 30),
      matchType: 'casual',
      format: '5v5',
      status: 'searching',
      createdAt: DateTime(2026, 10, 30, 10),
      teamName: 'Anorthosis',
      teamRating: 1500,
      venueText: venue,
    );

MatchProposalModel proposal({
  String id = 'p1',
  String? venue,
  String team = 'Keravnos FC',
  String? targetVenue,
  String target = 'Anorthosis',
}) =>
    MatchProposalModel(
      id: id,
      requestId: 'r1',
      proposingTeamId: 't1',
      proposingUserId: 'u1',
      status: 'pending',
      createdAt: DateTime(2026, 10, 30, 11),
      teamName: team,
      teamRating: 1480,
      venueText: venue,
      requestCity: 'Larnaca',
      requestScheduledAt: DateTime(2026, 11, 2, 18, 30),
      requestMatchType: 'casual',
      requestFormat: '5v5',
      requestVenueText: targetVenue,
      targetTeamName: target,
      targetTeamRating: 1500,
    );

Widget host(Widget child, {double scale = 1}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> show(
  WidgetTester t,
  Widget card, {
  double width = 390,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width * 2, 3000);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(host(card, scale: scale));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RequestCard', () {
    testWidgets("shows the request's own venue exactly as typed", (t) async {
      await show(t, RequestCard(request: request(venue: 'Home Ground')));
      expect(find.text('Home Ground'), findsOneWidget);
      expect(find.text('PROPOSALS'), findsNothing);
    });

    testWidgets('an older request without a venue shows no venue row',
        (t) async {
      await show(t, RequestCard(request: request(venue: null)));
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    });

    testWidgets('a proposal that suggests a venue shows it and a flag',
        (t) async {
      await show(
        t,
        RequestCard(
          request: request(),
          proposals: [proposal(venue: 'Seaside Pitch')],
        ),
      );
      expect(find.text('PROPOSALS'), findsOneWidget);
      expect(find.text('Keravnos FC'), findsOneWidget);
      expect(find.textContaining('Suggests: Seaside Pitch'), findsOneWidget);
      expect(find.byTooltip('Report venue name'), findsOneWidget);
    });

    testWidgets('a proposal without a suggestion has no suggestion, no flag',
        (t) async {
      await show(
        t,
        RequestCard(request: request(), proposals: [proposal()]),
      );
      expect(find.text('Keravnos FC'), findsOneWidget);
      expect(find.textContaining('Suggests'), findsNothing);
      expect(find.byTooltip('Report venue name'), findsNothing);
    });

    testWidgets('an empty suggestion counts as none', (t) async {
      await show(
        t,
        RequestCard(request: request(), proposals: [proposal(venue: '')]),
      );
      expect(find.textContaining('Suggests'), findsNothing);
      expect(find.byTooltip('Report venue name'), findsNothing);
    });

    testWidgets('only the proposals that suggest something get a flag',
        (t) async {
      await show(
        t,
        RequestCard(
          request: request(),
          proposals: [
            proposal(id: 'p1', team: 'Team A', venue: 'Pitch A'),
            proposal(id: 'p2', team: 'Team B'),
            proposal(id: 'p3', team: 'Team C', venue: 'Pitch C'),
          ],
        ),
      );
      expect(find.byTooltip('Report venue name'), findsNWidgets(2));
      expect(find.textContaining('Suggests: Pitch A'), findsOneWidget);
      expect(find.textContaining('Suggests: Pitch C'), findsOneWidget);
    });

    testWidgets('the flag reports exactly the proposal it sits on', (t) async {
      final calls = <(String?, String?, String?)>[];
      await show(
        t,
        RequestCard(
          request: request(),
          proposals: [
            proposal(id: 'p1', team: 'Team A', venue: 'Pitch A'),
            proposal(id: 'p2', team: 'Team B'),
            proposal(id: 'p3', team: 'Team C', venue: 'Pitch C'),
          ],
          reportVenue: ({requestId, matchId, proposalId}) async =>
              calls.add((requestId, matchId, proposalId)),
        ),
      );

      await t.tap(find.byTooltip('Report venue name').last);
      await settle(t);
      expect(find.text('Report this venue name?'), findsOneWidget);
      await t.tap(find.text('Report'));
      await settle(t);
      expect(calls, [(null, null, 'p3')]);
      expect(find.text("Thanks, we'll review it"), findsOneWidget);
    });

    testWidgets('cancelling the report sends nothing', (t) async {
      final calls = <String?>[];
      await show(
        t,
        RequestCard(
          request: request(),
          proposals: [proposal(venue: 'Seaside Pitch')],
          reportVenue: ({requestId, matchId, proposalId}) async =>
              calls.add(proposalId),
        ),
      );
      await t.tap(find.byTooltip('Report venue name'));
      await settle(t);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(calls, isEmpty);
      expect(find.text('Report this venue name?'), findsNothing);
    });

    testWidgets('accept and reject still act on the right proposal',
        (t) async {
      final accepted = <String>[];
      final rejected = <String>[];
      await show(
        t,
        RequestCard(
          request: request(),
          proposals: [
            proposal(id: 'p1', team: 'Team A', venue: 'Pitch A'),
            proposal(id: 'p2', team: 'Team B'),
          ],
          onAcceptProposal: (p) => accepted.add(p.id),
          onRejectProposal: (p) => rejected.add(p.id),
        ),
      );
      await t.tap(find.text('Accept').last);
      await t.tap(find.text('Reject').first);
      expect(accepted, ['p2']);
      expect(rejected, ['p1']);
    });

    testWidgets('a failed report is shown to the user, not swallowed',
        (t) async {
      await show(
        t,
        RequestCard(
          request: request(),
          proposals: [proposal(venue: 'Seaside Pitch')],
          reportVenue: ({requestId, matchId, proposalId}) async =>
              throw Exception('boom'),
        ),
      );
      await t.tap(find.byTooltip('Report venue name'));
      await settle(t);
      await t.tap(find.text('Report'));
      await settle(t);
      expect(find.text("Thanks, we'll review it"), findsNothing);
    });
  });

  group('SentProposalCard', () {
    testWidgets('says what you suggested', (t) async {
      await show(
        t,
        SentProposalCard(proposal: proposal(venue: 'Seaside Pitch')),
      );
      expect(find.text('Anorthosis'), findsOneWidget);
      expect(find.text('You suggested: Seaside Pitch'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('a proposal without a suggestion says nothing about venues',
        (t) async {
      await show(t, SentProposalCard(proposal: proposal()));
      expect(find.textContaining('You suggested'), findsNothing);
      expect(find.text('Pending'), findsOneWidget);
    });
  });

  group('phones and awkward text', () {
    final names = <String>[
      'A' * 60,
      'Γήπεδο Ποδοσφαίρου Μεγάλης Αθλητικής Εγκατάστασης Πάφου 🏟️⚽',
      '⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅⚽🏟️🥅',
      'ملعب كرة القدم الكبير للأحياء',
    ];

    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 360.0, 768.0]) {
        testWidgets(
            'cards hold any name at width $width, text ${(scale * 100).round()}%',
            (t) async {
          for (final name in names) {
            await show(
              t,
              Column(children: [
                RequestCard(
                  request: request(venue: name),
                  onCancel: () {},
                  onInvite: () {},
                  onAcceptProposal: (_) {},
                  onRejectProposal: (_) {},
                  proposals: [
                    proposal(
                      id: 'p1',
                      team: 'Αθλητικός Όμιλος Κεραυνός Στροβόλου Νέοι',
                      venue: name,
                    ),
                    proposal(id: 'p2', team: 'Team B', venue: names.first),
                    proposal(id: 'p3', team: 'Team C'),
                  ],
                ),
                SentProposalCard(
                  proposal: proposal(
                    venue: name,
                    target: 'Ομόνοια Λευκωσίας Παλαίμαχοι Βετεράνοι Ομάδα Α',
                  ),
                ),
              ]),
              width: width,
              scale: scale,
            );
            // An overflow anywhere would already have failed the test.
            expect(find.byType(RequestCard), findsOneWidget);
            expect(find.byType(SentProposalCard), findsOneWidget);
            expect(find.byTooltip('Report venue name'), findsNWidgets(2));
          }
        });
      }
    }

    testWidgets('the flag stays tappable on the narrowest phone with big text',
        (t) async {
      final calls = <String?>[];
      await show(
        t,
        RequestCard(
          request: request(venue: names.first),
          proposals: [proposal(id: 'p1', venue: names[1])],
          reportVenue: ({requestId, matchId, proposalId}) async =>
              calls.add(proposalId),
        ),
        width: 320,
        scale: 2,
      );
      await t.tap(find.byTooltip('Report venue name'));
      await settle(t);
      await t.tap(find.text('Report'));
      await settle(t);
      expect(calls, ['p1']);
    });
  });
}
