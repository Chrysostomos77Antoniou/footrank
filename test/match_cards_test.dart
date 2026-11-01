// The cards of the Matches screen, one at a time. They only call back, so
// everything they promise is checked here: who and how strong, when and where,
// what you can do, and that two buttons side by side are the same height and
// nothing spills out of the card on the narrowest phone with the largest text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/segmented_tabs.dart';
import 'package:footrank/match/presentation/widgets/match_cards.dart';
import 'package:footrank/match/presentation/widgets/match_formatters.dart';
import 'package:footrank/models/match_payment_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/payment/data/payment_repository.dart';
import 'package:footrank/payment/presentation/widgets/pay_fee_button.dart';

import 'support/matches_fixtures.dart';

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> _show(
  WidgetTester t,
  Widget card, {
  double width = 390,
  double textScale = 1,
}) async {
  t.view.physicalSize = Size(width * 2, 3000);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(_host(card, textScale: textScale));
  await t.pump();
}

Finder _button(String label) => find.widgetWithText(AppButton, label);

void main() {
  group('OpponentCard', () {
    OpponentCard card({
      String? venue = 'Larnaca Stadium',
      int rating = 1820,
      int? mine = 1700,
      String type = 'ranked',
      String name = 'Anorthosis',
      VoidCallback? onPropose,
    }) =>
        OpponentCard(
          opponent: request('o1', name, rating, venue: venue, type: type),
          myRating: mine,
          onPropose: onPropose ?? () {},
        );

    testWidgets('says who, how strong, when, what kind and where', (t) async {
      final c = card();
      await _show(t, c);

      expect(find.text('Anorthosis'), findsOneWidget);
      expect(find.text('1820 PWR · 120 above you'), findsOneWidget);
      expect(find.text('Ranked'), findsOneWidget);
      expect(find.text('${formatMatchWhen(c.opponent.scheduledAt)} · 5v5'),
          findsOneWidget);
      expect(find.text('Larnaca Stadium'), findsOneWidget);
      expect(find.byTooltip('Report venue name'), findsOneWidget);
      expect(_button('Propose Match'), findsOneWidget);
    });

    testWidgets('compares the other team with yours, in either direction',
        (t) async {
      await _show(t, card(rating: 1550, mine: 1700));
      expect(find.text('1550 PWR · 150 below you'), findsOneWidget);

      await _show(t, card(rating: 1710, mine: 1700));
      expect(find.text('1710 PWR · Evenly matched'), findsOneWidget);
    });

    testWidgets('shows only the rating when it does not know yours',
        (t) async {
      await _show(t, card(mine: null));
      expect(find.text('1820 PWR'), findsOneWidget);
    });

    testWidgets('a request without a venue has no pin and no report flag',
        (t) async {
      await _show(t, card(venue: null));
      expect(find.byIcon(Icons.place_outlined), findsNothing);
      expect(find.byTooltip('Report venue name'), findsNothing);
    });

    testWidgets('a casual request is labelled casual', (t) async {
      await _show(t, card(type: 'casual'));
      expect(find.text('Casual'), findsOneWidget);
      expect(find.text('Ranked'), findsNothing);
    });

    testWidgets('Propose Match calls back, once', (t) async {
      var proposed = 0;
      await _show(t, card(onPropose: () => proposed++));

      await t.tap(_button('Propose Match'));
      expect(proposed, 1);
    });

    testWidgets('a very long team name stays inside the card on the narrowest '
        'phone at the largest text size', (t) async {
      await _show(
        t,
        card(name: 'Strovolos United With A Very Long Name FC', rating: 2100),
        width: 320,
        textScale: 2,
      );

      expect(t.takeException(), isNull);
      final frame = t.getRect(find.byType(MatchCardFrame));
      final button = t.getRect(_button('Propose Match'));
      expect(button.left, greaterThanOrEqualTo(frame.left));
      expect(button.right, lessThanOrEqualTo(frame.right));
      expect(t.getRect(find.text('Ranked')).right,
          lessThanOrEqualTo(frame.right));
    });
  });

  group('RequestCard', () {
    final mine = request('r1', 'FC Elite', 1700,
        venue: 'Home Ground', teamId: 'my', day: 1, hour: 20);

    testWidgets('lists the proposals it received, with a count and how strong '
        'each team is', (t) async {
      await _show(
        t,
        RequestCard(
          request: mine,
          proposals: [
            proposal('p1', 'r1', 'Omonia 29', 1760),
            proposal('p2', 'r1', 'APOEL Legends', 1590),
          ],
        ),
      );

      expect(find.text('PROPOSALS'), findsOneWidget);
      expect(find.widgetWithText(CountBadge, '2'), findsOneWidget);
      expect(find.text('Omonia 29'), findsOneWidget);
      expect(find.text('1760 PWR · 60 above you'), findsOneWidget);
      expect(find.text('APOEL Legends'), findsOneWidget);
      expect(find.text('1590 PWR · 110 below you'), findsOneWidget);
    });

    testWidgets('the proposals count is a small pill next to the word, not a '
        'bar across the card', (t) async {
      await _show(
        t,
        RequestCard(
          request: mine,
          proposals: [
            proposal('p1', 'r1', 'Omonia 29', 1760),
            proposal('p2', 'r1', 'APOEL Legends', 1590),
          ],
        ),
      );

      final word = t.getRect(find.text('PROPOSALS'));
      final badge = t.getRect(find.byType(CountBadge));
      expect(badge.width, lessThan(48));
      expect(badge.left, greaterThan(word.right));
      expect((badge.center.dy - word.center.dy).abs(), lessThan(4));
    });

    testWidgets('without proposals there is no proposals section', (t) async {
      await _show(t, RequestCard(request: mine));
      expect(find.text('PROPOSALS'), findsNothing);
      expect(_button('Accept'), findsNothing);
    });

    testWidgets('accepting or rejecting reports the proposal it was tapped on',
        (t) async {
      final accepted = <String>[];
      final rejected = <String>[];
      await _show(
        t,
        RequestCard(
          request: mine,
          proposals: [
            proposal('p1', 'r1', 'Omonia 29', 1760),
            proposal('p2', 'r1', 'APOEL Legends', 1590),
          ],
          onAcceptProposal: (p) => accepted.add(p.id),
          onRejectProposal: (p) => rejected.add(p.id),
        ),
      );

      await t.tap(_button('Accept').last);
      await t.tap(_button('Reject').first);

      expect(accepted, ['p2']);
      expect(rejected, ['p1']);
    });

    testWidgets('Reject and Accept sit side by side at the same height',
        (t) async {
      await _show(
        t,
        RequestCard(
          request: mine,
          proposals: [proposal('p1', 'r1', 'Omonia 29', 1760)],
          onAcceptProposal: (_) {},
          onRejectProposal: (_) {},
        ),
      );

      final reject = t.getRect(_button('Reject'));
      final accept = t.getRect(_button('Accept'));
      expect(reject.height, AppSemantic.minTapTarget);
      expect(accept.height, AppSemantic.minTapTarget);
      expect(reject.top, accept.top);
      expect(reject.right, lessThan(accept.left));
    });

    testWidgets('shows the cancel and invite buttons only when they can be '
        'used', (t) async {
      var cancelled = 0;
      await _show(t, RequestCard(request: mine));
      expect(find.byTooltip('Cancel request'), findsNothing);
      expect(find.byTooltip('Invite a rival team'), findsNothing);

      await _show(
        t,
        RequestCard(
          request: mine,
          onCancel: () => cancelled++,
          onInvite: () {},
        ),
      );
      await t.tap(find.byTooltip('Cancel request'));
      expect(cancelled, 1);
      expect(find.byTooltip('Invite a rival team'), findsOneWidget);
    });
  });

  group('SentProposalCard', () {
    testWidgets('shows who it was sent to, how strong they are and what is '
        'pending', (t) async {
      final p = sentProposal('s1', 'Anorthosis', 1820,
          venue: 'Our pitch behind the school');
      await _show(t, SentProposalCard(proposal: p, myRating: 1700));

      expect(find.text('Anorthosis'), findsOneWidget);
      expect(find.text('1820 PWR · 120 above you'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text(formatMatchWhen(p.requestScheduledAt!)), findsOneWidget);
      expect(find.text('Larnaca · Ranked · 5v5'), findsOneWidget);
      expect(find.text('You suggested: Our pitch behind the school'),
          findsOneWidget);
    });

    testWidgets('a proposal without a venue suggestion shows none',
        (t) async {
      await _show(
        t,
        SentProposalCard(
            proposal: sentProposal('s2', 'Keravnos FC', 1690), myRating: 1700),
      );
      expect(find.textContaining('You suggested'), findsNothing);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    });

    testWidgets('has no buttons: only the other captain can act on it',
        (t) async {
      await _show(
        t,
        SentProposalCard(
            proposal: sentProposal('s2', 'Keravnos FC', 1690), myRating: 1700),
      );
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('copes with a proposal whose request details are missing',
        (t) async {
      final bare = MatchProposalModel(
        id: 'p',
        requestId: 'r',
        proposingTeamId: 'my',
        proposingUserId: 'u',
        status: 'pending',
        createdAt: DateTime.now(),
      );
      await _show(t, SentProposalCard(proposal: bare));
      expect(find.text('Unknown team'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('PendingMatchCard', () {
    PendingMatchCard card({
      bool iConfirmed = false,
      bool canAct = true,
      VoidCallback? onConfirm,
      VoidCallback? onReject,
    }) =>
        PendingMatchCard(
          match: fixture('m3', 'pending',
              day: 3, away: 'Omonia 29', awayRating: 1760, venue: 'Seaside Pitch'),
          iConfirmed: iConfirmed,
          canAct: canAct,
          onConfirm: onConfirm ?? () {},
          onReject: onReject ?? () {},
        );

    testWidgets('shows both teams with their strength and record, and the '
        'venue', (t) async {
      await _show(t, card());

      expect(find.text('FC Elite'), findsOneWidget);
      expect(find.text('1700 PWR'), findsOneWidget);
      expect(find.text('5W · 2L'), findsOneWidget);
      expect(find.text('Omonia 29'), findsOneWidget);
      expect(find.text('1760 PWR'), findsOneWidget);
      expect(find.text('Seaside Pitch'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Larnaca · Ranked · 5v5'), findsOneWidget);
    });

    testWidgets('a captain who has not answered can reject or confirm, side '
        'by side at the same height', (t) async {
      var confirmed = 0;
      var rejected = 0;
      await _show(
          t, card(onConfirm: () => confirmed++, onReject: () => rejected++));

      final reject = t.getRect(_button('Reject'));
      final confirm = t.getRect(_button('Confirm'));
      expect(reject.height, AppSemantic.minTapTarget);
      expect(confirm.height, AppSemantic.minTapTarget);
      expect(reject.top, confirm.top);
      expect(reject.right, lessThan(confirm.left));

      await t.tap(_button('Confirm'));
      await t.tap(_button('Reject'));
      expect(confirmed, 1);
      expect(rejected, 1);
    });

    testWidgets('once you have confirmed, only the way out is left and the '
        'card says it is waiting', (t) async {
      var rejected = 0;
      await _show(t, card(iConfirmed: true, onReject: () => rejected++));

      expect(find.text('You have confirmed. Waiting for the other captain.'),
          findsOneWidget);
      expect(_button('Confirm'), findsNothing);

      final reject = t.getRect(_button('Reject'));
      final frame = t.getRect(find.byType(MatchCardFrame));
      expect(reject.width, lessThan(frame.width / 2),
          reason: 'it keeps to its own width');

      await t.tap(_button('Reject'));
      expect(rejected, 1);
    });

    testWidgets('a member who is not the captain sees no buttons and is told '
        'why', (t) async {
      await _show(t, card(canAct: false));

      expect(find.text('Only your captain can confirm or reject'),
          findsOneWidget);
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('holds together on the narrowest phone at the largest text '
        'size', (t) async {
      await _show(t, card(), width: 320, textScale: 2);
      expect(t.takeException(), isNull);

      final frame = t.getRect(find.byType(MatchCardFrame));
      for (final label in ['Reject', 'Confirm']) {
        final r = t.getRect(_button(label));
        expect(r.left, greaterThanOrEqualTo(frame.left), reason: label);
        expect(r.right, lessThanOrEqualTo(frame.right), reason: label);
      }
    });
  });

  group('MatchCard', () {
    MatchCard card(
      String status, {
      int? home,
      int? away,
      String myTeam = 'my',
      PendingFee? fee,
    }) =>
        MatchCard(
          match: fixture('m1', status, homeScore: home, awayScore: away),
          myTeamId: myTeam,
          pendingFee: fee,
          onPaid: () {},
        );

    testWidgets('a confirmed match shows when, where, both teams and its '
        'status', (t) async {
      final c = card('confirmed');
      await _show(t, c);

      expect(find.text(formatMatchWhen(c.match.scheduledAt)), findsOneWidget);
      expect(find.text('Larnaca · Ranked · 5v5'), findsOneWidget);
      expect(find.text('FC Elite'), findsOneWidget);
      expect(find.text('Keravnos FC'), findsOneWidget);
      expect(find.text('1700 PWR'), findsOneWidget);
      expect(find.text('1690 PWR'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('vs'), findsOneWidget);
    });

    testWidgets('a match with nothing owed has no fee line', (t) async {
      await _show(t, card('confirmed'));
      expect(find.text('Team fee due'), findsNothing);
      expect(find.byType(PayFeeButton), findsNothing);
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('a fee that is due sits under a rule, with the pay button at '
        'the far end', (t) async {
      // Wide enough for the message and the button to share a line even when
      // the test font draws every letter a full em wide.
      await _show(t, card('confirmed', fee: feeFor('m1')), width: 640);

      expect(find.text('Team fee due'), findsOneWidget);
      expect(find.byType(PayFeeButton), findsOneWidget);

      final rule = t.getRect(find.byType(Divider));
      final label = t.getRect(find.text('Team fee due'));
      final pay = t.getRect(find.byType(PayFeeButton));
      expect(rule.bottom, lessThan(label.top));
      expect(pay.left, greaterThan(label.right));
      expect(pay.right, closeTo(rule.right, 1));
    });

    testWidgets('a payment that failed says the team is not covered',
        (t) async {
      final failed = PendingFee(
        matchId: 'm1',
        teamId: 'my',
        homeTeamName: 'FC Elite',
        awayTeamName: 'Keravnos FC',
        scheduledAt: at(2, 20, 30),
        city: 'Larnaca',
        payment: MatchPaymentModel(
          id: 'pay1',
          matchId: 'm1',
          teamId: 'my',
          captainId: 'cap',
          status: 'failed',
          createdAt: DateTime.now(),
        ),
      );
      await _show(t, card('confirmed', fee: failed));

      expect(find.text('Payment failed — your team is not covered'),
          findsOneWidget);
      expect(find.text('Team fee due'), findsNothing);
    });

    testWidgets('the fee line drops under its message instead of being '
        'squeezed on the narrowest phone at the largest text', (t) async {
      await _show(t, card('confirmed', fee: feeFor('m1')),
          width: 320, textScale: 2);

      expect(t.takeException(), isNull);
      final label = t.getRect(find.text('Team fee due'));
      final pay = t.getRect(find.byType(PayFeeButton));
      final frame = t.getRect(find.byType(MatchCardFrame));
      expect(pay.right, lessThanOrEqualTo(frame.right));
      expect(label.right, lessThanOrEqualTo(frame.right));
      expect(label.width, greaterThan(60), reason: 'not a sliver');
    });

    testWidgets('a won match says WON with the score', (t) async {
      await _show(t, card('completed', home: 4, away: 2));
      expect(find.text('WON'), findsOneWidget);
      expect(find.text('4 – 2'), findsOneWidget);
      expect(find.text('vs'), findsNothing);
    });

    testWidgets('a lost match says LOST, a level one DRAW', (t) async {
      await _show(t, card('completed', home: 1, away: 3));
      expect(find.text('LOST'), findsOneWidget);

      await _show(t, card('completed', home: 2, away: 2));
      expect(find.text('DRAW'), findsOneWidget);
    });

    testWidgets('the result is read from the side of the team you are acting '
        'as', (t) async {
      // 1 - 3 from the home side's point of view: the away team won.
      await _show(t, card('completed', home: 1, away: 3, myTeam: 'opp-m1'));
      expect(find.text('WON'), findsOneWidget);
    });

    testWidgets('a finished match without a score claims no result',
        (t) async {
      await _show(t, card('completed'));
      expect(find.text('WON'), findsNothing);
      expect(find.text('LOST'), findsNothing);
      expect(find.text('DRAW'), findsNothing);
    });
  });

  group('MatchPill', () {
    testWidgets('stops growing with the text size at 1.3x', (t) async {
      Future<double> widthAt(double scale) async {
        await _show(
          t,
          const Align(
            alignment: Alignment.centerLeft,
            child: MatchPill(label: 'Ranked', color: Colors.green),
          ),
          textScale: scale,
        );
        return t.getSize(find.byType(MatchPill)).width;
      }

      final atLimit = await widthAt(1.3);
      expect(await widthAt(3), atLimit);
      expect(atLimit, greaterThan(await widthAt(1)));
    });
  });
}
