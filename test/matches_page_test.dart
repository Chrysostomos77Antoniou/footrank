// The Matches screen as a whole, on a phone-sized screen, with repositories
// that answer from memory: what each tab shows, what every empty list says,
// what filtering asks the server (and what it does not), what happens when a
// list will not load, and the two decisions a captain makes with numbers in
// front of them -- proposing a match and accepting a proposal -- where the
// Pitch Power preview has to be about THAT opponent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/match/presentation/widgets/venue_map_picker.dart';
import 'package:footrank/models/venue_location.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/pitch_power_preview.dart';
import 'package:footrank/core/widgets/segmented_tabs.dart';
import 'package:footrank/match/presentation/widgets/match_cards.dart';
import 'package:footrank/match/presentation/widgets/opponent_filters.dart';
import 'package:footrank/match/presentation/widgets/team_switcher.dart';

import 'support/matches_fixtures.dart';

const _lists = ['requests', 'matches', 'opponents', 'incoming', 'sent'];
const _summary = 'Larnaca · Any type · Any date';

Finder _tab(String label) => find.descendant(
      of: find.byType(SegmentedTabs),
      matching: find.text(label),
    );

Finder _pill(String label) => find.descendant(
      of: find.byType(FilterPills),
      matching: find.text(label),
    );

/// A pill of the filter panel (the panel also has an "Any" of its own, for the
/// power range, so these are looked for inside its pills only).
Finder _filterPill(String label) => find.descendant(
      of: find.descendant(
        of: find.byType(OpponentFilters),
        matching: find.byType(FilterPills),
      ),
      matching: find.text(label),
    );

Finder _button(String label) => find.widgetWithText(AppButton, label);

Finder _inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

Future<void> _openTab(WidgetTester t, String label) async {
  await t.tap(_tab(label));
  await settle(t);
}

Future<void> _openPill(WidgetTester t, String label) async {
  await t.ensureVisible(_pill(label));
  await t.tap(_pill(label));
  await settle(t);
}

Future<void> _openFilters(WidgetTester t) async {
  await t.tap(find.text(_summary));
  await settle(t);
}

/// Pulls the list down, the way a thumb would. A refresh arms after a quarter
/// of the list's height, so the pull is measured against it: a tall test
/// screen needs a longer pull than a phone.
Future<void> _pullToRefresh(WidgetTester t) async {
  final list = find
      .descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      )
      .first;
  await t.fling(list, Offset(0, t.getSize(list).height * 0.4), 3000);
  await settle(t, frames: 20);
}

/// Opens every tab and every pill, and the filters.
Future<void> _lookAtEverything(WidgetTester t) async {
  await _openFilters(t);
  await _openTab(t, 'Activity');
  for (final pill in ['Requests', 'Sent', 'To confirm']) {
    await _openPill(t, pill);
  }
  await _openTab(t, 'Matches');
  for (final pill in ['Upcoming', 'History']) {
    await _openPill(t, pill);
  }
  await _openTab(t, 'Opponents');
}

/// Answers every Pitch Power preview with the same numbers and remembers who
/// it was asked about.
class _Stakes {
  final asked = <({String teamId, String matchType, String? opponentTeamId})>[];

  Future<PitchPowerDeltas> call({
    required String teamId,
    required String matchType,
    String? opponentTeamId,
  }) async {
    asked.add((
      teamId: teamId,
      matchType: matchType,
      opponentTeamId: opponentTeamId,
    ));
    return (win: 47, draw: 0, loss: -34);
  }
}

void main() {
  group('Opponents', () {
    testWidgets('lists every open request and counts them', (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);

      expect(find.text('4 open requests'), findsOneWidget);
      expect(find.byType(OpponentCard), findsNWidgets(4));
      expect(find.text('Anorthosis'), findsOneWidget);
      expect(find.text('Create Match'), findsOneWidget);
    });

    testWidgets('one request is not "1 open requests"', (t) async {
      final d = busyTeam()..opponents = [request('o1', 'Anorthosis', 1820)];
      await pumpMatchesPage(t, d);

      expect(find.text('1 open request'), findsOneWidget);
    });

    testWidgets('a team far stronger than yours can still be proposed to: the '
        'captain decides, nothing hides it', (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);

      // 2100 against 1700 is 400 apart. It used to be refused beyond 150.
      expect(find.text('2100 PWR · 400 above you'), findsOneWidget);
      expect(find.text('1550 PWR · 150 below you'), findsOneWidget);
      final buttons = t.widgetList<AppButton>(_button('Propose Match'));
      expect(buttons, hasLength(4));
      expect(buttons.every((b) => b.onPressed != null), isTrue);
    });

    testWidgets('the screen compares everyone with the team you act as',
        (t) async {
      final d = busyTeam()
        ..teams = [
          team('my', 'FC Elite', 1700),
          team('t2', 'Barcelona', 1510, city: 'Limassol'),
        ];
      await pumpMatchesPage(t, d, height: 2600);

      expect(find.byType(TeamSwitcher), findsOneWidget);
      expect(find.text('2100 PWR · 400 above you'), findsOneWidget);
      expect(d.cityQueries.single.excludeTeamId, 'my');

      await t.tap(find.descendant(
        of: find.byType(TeamSwitcher),
        matching: find.text('Barcelona'),
      ));
      await settle(t);

      expect(d.cityQueries.last.excludeTeamId, 't2');
      expect(d.cityQueries.last.city, 'Limassol');
      expect(find.text('2100 PWR · 590 above you'), findsOneWidget);
      expect(d.callsTo('opponents'), 2);
    });

    testWidgets('a single team has no switcher to choose from', (t) async {
      await pumpMatchesPage(t, busyTeam());

      expect(find.byType(TeamSwitcher), findsNothing);
    });
  });

  group('Tabs', () {
    testWidgets('say what is waiting for a captain: proposals and matches to '
        'confirm on Activity, fees due on Matches', (t) async {
      final handle = t.ensureSemantics();
      await pumpMatchesPage(t, busyTeam());

      // 2 proposals received + 2 matches that need a confirmation.
      expect(find.bySemanticsLabel('Activity, 4'), findsOneWidget);
      // 1 fee still to pay.
      expect(find.bySemanticsLabel('Matches, 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Opponents'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('do not nudge a player about what only the captain can do',
        (t) async {
      final d = busyTeam()..fees = [];
      await pumpMatchesPage(t, d, height: 2600, userId: 'u3');

      expect(find.descendant(
        of: find.byType(SegmentedTabs),
        matching: find.byType(CountBadge),
      ), findsNothing);
      // Proposals are for the captain: they are not even fetched.
      expect(d.callsTo('incoming'), 0);

      await _openTab(t, 'Activity');
      expect(find.byType(RequestCard), findsNWidgets(2));
      expect(find.text('PROPOSALS'), findsNothing);
      expect(find.byTooltip('Cancel request'), findsNothing);

      await _openPill(t, 'To confirm');
      expect(find.byType(PendingMatchCard), findsNWidgets(2));
      expect(find.text('Only your captain can confirm or reject'),
          findsNWidgets(2));
      expect(_button('Confirm'), findsNothing);
    });

    testWidgets('switching tabs fetches nothing again and keeps the pill you '
        'were on', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      final fetched = d.calls.length;

      await _openTab(t, 'Activity');
      await _openPill(t, 'Sent');
      await _openTab(t, 'Matches');
      await _openPill(t, 'History');
      await _openTab(t, 'Opponents');
      await _openTab(t, 'Activity');

      expect(d.calls, hasLength(fetched));
      expect(find.byType(SentProposalCard), findsNWidgets(2));
      expect(find.byType(RequestCard), findsNothing);

      await _openTab(t, 'Matches');
      expect(find.text('WON'), findsOneWidget);
    });

    testWidgets('a tab shows its list the moment it is opened', (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);

      await t.tap(_tab('Activity'));
      await t.pump();

      expect(find.byType(RequestCard), findsNWidgets(2));
    });
  });

  group('Activity', () {
    testWidgets('Requests: each request with the proposals it received',
        (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);
      await _openTab(t, 'Activity');

      expect(find.byType(RequestCard), findsNWidgets(2));
      expect(find.text('Omonia 29'), findsOneWidget);
      expect(find.text('APOEL Legends'), findsOneWidget);
      expect(find.text('1760 PWR · 60 above you'), findsOneWidget);
      expect(find.text('1590 PWR · 110 below you'), findsOneWidget);
    });

    testWidgets('Sent: the proposals your team made, still waiting',
        (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);
      await _openTab(t, 'Activity');
      await _openPill(t, 'Sent');

      expect(find.byType(SentProposalCard), findsNWidgets(2));
      expect(find.text('You suggested: Our pitch behind the school'),
          findsOneWidget);
    });

    testWidgets('To confirm: matches both captains still have to agree on',
        (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);
      await _openTab(t, 'Activity');
      await _openPill(t, 'To confirm');

      expect(find.byType(PendingMatchCard), findsNWidgets(2));
      // One is already confirmed on your side, one is waiting for you.
      expect(find.text('You have confirmed. Waiting for the other captain.'),
          findsOneWidget);
      expect(_button('Confirm'), findsOneWidget);
    });

    testWidgets('declining a proposal tells the server which one',
        (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      await _openTab(t, 'Activity');

      await t.tap(_button('Reject').last);
      await settle(t);

      expect(d.rejected, ['p2']);
      expect(find.text('Proposal declined'), findsOneWidget);
      expect(d.callsTo('incoming'), 2);
    });

    testWidgets('confirming a match tells the server which one', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      await _openTab(t, 'Activity');
      await _openPill(t, 'To confirm');

      await t.tap(_button('Confirm'));
      await settle(t);

      expect(d.confirmed, ['m7']);
      expect(find.text('Match confirmed!'), findsOneWidget);
    });

    testWidgets('rejecting a match asks first, and only then removes it',
        (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      await _openTab(t, 'Activity');
      await _openPill(t, 'To confirm');

      await t.tap(_button('Reject').first);
      await settle(t);
      expect(find.text('Reject this match?'), findsOneWidget);

      await t.tap(_inDialog('Keep'));
      await settle(t);
      expect(d.cancelledMatches, isEmpty);
      expect(find.text('Reject this match?'), findsNothing);

      await t.tap(_button('Reject').first);
      await settle(t);
      await t.tap(_inDialog('Reject'));
      await settle(t);
      expect(d.cancelledMatches, ['m3']);
      expect(find.text('Match rejected'), findsOneWidget);
    });

    testWidgets('cancelling a request asks first, and only then removes it',
        (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      await _openTab(t, 'Activity');

      await t.tap(find.byTooltip('Cancel request').first);
      await settle(t);
      expect(find.text('Cancel match request?'), findsOneWidget);

      await t.tap(_inDialog('Keep'));
      await settle(t);
      expect(d.deletedRequests, isEmpty);

      await t.tap(find.byTooltip('Cancel request').first);
      await settle(t);
      await t.tap(_inDialog('Cancel Request'));
      await settle(t);
      expect(d.deletedRequests, ['r1']);
      expect(find.text('Match request cancelled'), findsOneWidget);
    });
  });

  group('Matches', () {
    testWidgets('Upcoming: confirmed matches, soonest first, the fee due '
        'where it belongs', (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);
      await _openTab(t, 'Matches');

      expect(find.byType(MatchCard), findsNWidgets(2));
      expect(find.text('Team fee due'), findsOneWidget);
      final first = t.getTopLeft(find.byType(MatchCard).at(0)).dy;
      final second = t.getTopLeft(find.byType(MatchCard).at(1)).dy;
      expect(first, lessThan(second));
      // The one with the fee is the sooner of the two.
      expect(
        find.descendant(
          of: find.byType(MatchCard).first,
          matching: find.text('Team fee due'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('History: what was played, latest first, with the result',
        (t) async {
      await pumpMatchesPage(t, busyTeam(), height: 2600);
      await _openTab(t, 'Matches');
      await _openPill(t, 'History');

      expect(find.byType(MatchCard), findsNWidgets(3));
      expect(find.text('Team fee due'), findsNothing);
      final won = t.getTopLeft(find.text('WON')).dy;
      final lost = t.getTopLeft(find.text('LOST')).dy;
      final draw = t.getTopLeft(find.text('DRAW')).dy;
      expect(won, lessThan(lost));
      expect(lost, lessThan(draw));
    });
  });

  group('Empty lists say what to do next', () {
    testWidgets('Opponents', (t) async {
      await pumpMatchesPage(t, MatchesData());

      expect(find.text('No open requests right now'), findsOneWidget);
      expect(find.text('Post a Request'), findsNothing);
      expect(find.text('Reset filters'), findsNothing);
      expect(find.text('Create Match'), findsOneWidget);
    });

    testWidgets('Opponents of a team that cannot field five players yet',
        (t) async {
      final d = MatchesData()..memberCount = 4;
      await pumpMatchesPage(t, d);

      expect(find.text('No teams are searching right now'), findsOneWidget);
    });

    testWidgets('Opponents, once a filter is on: say so and offer to undo it',
        (t) async {
      final d = MatchesData();
      // Tall enough that the open panel and the empty state both fit, clear of
      // the Create Match button floating over the bottom of the list.
      await pumpMatchesPage(t, d, height: 1400);

      await _openFilters(t);
      await t.tap(_filterPill('Casual'));
      await settle(t);

      expect(find.text('No open requests match your filters'),
          findsOneWidget);
      final reset = find.descendant(
        of: find.byType(EmptyView),
        matching: find.text('Reset filters'),
      );
      expect(reset, findsOneWidget);

      await t.tap(reset);
      await settle(t);

      expect(d.cityQueries.last.matchType, isNull);
      expect(find.text('No open requests right now'), findsOneWidget);
      expect(find.text(_summary), findsOneWidget);
    });

    testWidgets('Activity and Matches', (t) async {
      await pumpMatchesPage(t, MatchesData());

      await _openTab(t, 'Activity');
      expect(find.text('No open requests'), findsOneWidget);
      await _openPill(t, 'Sent');
      expect(find.text('No pending proposals'), findsOneWidget);
      await _openPill(t, 'To confirm');
      expect(find.text('Nothing to confirm'), findsOneWidget);

      await _openTab(t, 'Matches');
      expect(find.text('No upcoming matches'), findsOneWidget);
      await _openPill(t, 'History');
      expect(find.text('No past matches yet'), findsOneWidget);
    });

    testWidgets('a player with no team is told to join or create one',
        (t) async {
      final d = MatchesData()..teams = [];
      await pumpMatchesPage(t, d);

      expect(find.text('No team yet'), findsOneWidget);
      expect(find.byType(SegmentedTabs), findsNothing);
      expect(find.text('Create Match'), findsNothing);
      expect(d.calls, isEmpty);
    });
  });

  group('Filters', () {
    testWidgets('start folded into one line that says what you are looking at',
        (t) async {
      await pumpMatchesPage(t, busyTeam());

      expect(find.text(_summary), findsOneWidget);
      expect(find.text('Match type'), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('a match type asks the server again, with that type',
        (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      expect(d.cityQueries.single.matchType, isNull);

      await _openFilters(t);
      await t.tap(_filterPill('Casual'));
      await settle(t);
      expect(d.cityQueries.last.matchType, 'casual');
      expect(d.cityQueries.last.city, 'Larnaca');
      expect(d.cityQueries.last.excludeTeamId, 'my');
      expect(find.text('Larnaca · Casual · Any date'), findsOneWidget);

      await t.tap(_filterPill('Ranked'));
      await settle(t);
      expect(d.cityQueries.last.matchType, 'ranked');

      await t.tap(_filterPill('Any'));
      await settle(t);
      expect(d.cityQueries.last.matchType, isNull);
      expect(d.callsTo('opponents'), 4);
    });

    testWidgets('the panel offers a way back as soon as something is on',
        (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      await _openFilters(t);
      expect(_button('Reset filters'), findsNothing);

      await t.tap(_filterPill('Casual'));
      await settle(t);
      expect(_button('Reset filters'), findsOneWidget);

      await t.tap(_button('Reset filters'));
      await settle(t);
      expect(d.cityQueries.last.matchType, isNull);
      expect(find.text(_summary), findsOneWidget);
      expect(_button('Reset filters'), findsNothing);
    });

    testWidgets('the power range narrows the list already on screen, without '
        'asking the server again', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      await _openFilters(t);

      // What the slider does when a finger lifts at 100.
      t.widget<Slider>(find.byType(Slider)).onChangeEnd!(100);
      await settle(t);

      expect(d.callsTo('opponents'), 1);
      expect(find.text('1 open request'), findsOneWidget);
      expect(find.text('Keravnos FC'), findsOneWidget);
      expect(find.text('Anorthosis'), findsNothing);
      expect(find.text('Larnaca · Any type · Any date · ±100 PWR'),
          findsOneWidget);

      t.widget<Slider>(find.byType(Slider)).onChangeEnd!(0);
      await settle(t);
      expect(find.text('4 open requests'), findsOneWidget);
      expect(d.callsTo('opponents'), 1);
    });

    testWidgets('dragging the power range slider with a finger works too',
        (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      await _openFilters(t);
      expect(find.text('Any'), findsNWidgets(2));

      await t.drag(find.byType(Slider), const Offset(900, 0));
      await settle(t);

      expect(find.text('±500 PWR'), findsOneWidget);
      expect(d.callsTo('opponents'), 1);
      // 500 is wider than any team here is from yours.
      expect(find.text('4 open requests'), findsOneWidget);
    });

    testWidgets('a range with nobody in it says so, and resetting brings '
        'everyone back', (t) async {
      final d = busyTeam()
        ..opponents = [
          request('o1', 'Anorthosis', 1820),
          request('o3', 'AEK Veterans', 1550),
        ];
      await pumpMatchesPage(t, d, height: 1400);
      await _openFilters(t);

      t.widget<Slider>(find.byType(Slider)).onChangeEnd!(100);
      await settle(t);
      expect(find.text('No teams in that power range'), findsOneWidget);

      await t.tap(find.descendant(
        of: find.byType(EmptyView),
        matching: find.text('Reset filters'),
      ));
      await settle(t);

      expect(find.text('2 open requests'), findsOneWidget);
      expect(find.text('No teams in that power range'), findsNothing);
    });
  });

  group('When a list will not load', () {
    testWidgets('it says so with a way to try again, and the others carry on',
        (t) async {
      final d = busyTeam()..failing.add('opponents');
      await pumpMatchesPage(t, d, height: 2600);

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.byType(OpponentCard), findsNothing);
      // The filters stay: they are how you change what you are asking for.
      expect(find.text(_summary), findsOneWidget);

      await _openTab(t, 'Activity');
      expect(find.byType(RequestCard), findsNWidgets(2));
      await _openTab(t, 'Opponents');

      d.failing.clear();
      await t.tap(find.text('Try again'));
      await settle(t);

      expect(find.byType(ErrorView), findsNothing);
      expect(find.byType(OpponentCard), findsNWidgets(4));
      expect(d.callsTo('opponents'), 2);
    });

    testWidgets('before the first answer there is a skeleton, not an empty '
        'state that would be a lie', (t) async {
      final d = busyTeam()..never = true;
      await pumpMatchesPage(t, d);

      expect(find.byType(MatchListSkeleton), findsOneWidget);
      expect(find.text('No open requests right now'), findsNothing);
      expect(find.byType(ErrorView), findsNothing);
      // The page around it is already there.
      expect(find.text('Create Match'), findsOneWidget);
      expect(find.text(_summary), findsOneWidget);

      await _openTab(t, 'Activity');
      expect(find.byType(MatchListSkeleton), findsOneWidget);
      expect(find.text('No open requests'), findsNothing);
    });

    testWidgets('pulling down fetches everything again', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);
      for (final list in _lists) {
        expect(d.callsTo(list), 1, reason: list);
      }

      await _pullToRefresh(t);

      for (final list in _lists) {
        expect(d.callsTo(list), 2, reason: list);
      }
      expect(find.byType(OpponentCard), findsNWidgets(4));
    });

    testWidgets('a refresh that fails keeps what was on screen and says so',
        (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600);

      d.failing.add('opponents');
      await _pullToRefresh(t);

      expect(find.byType(OpponentCard), findsNWidgets(4));
      expect(find.byType(ErrorView), findsNothing);
      expect(find.text('opponents could not be loaded'), findsOneWidget);
    });
  });

  group('Create Match', () {
    testWidgets('is always one tap away, and says why when the team is too '
        'small to field a match', (t) async {
      final d = busyTeam()..memberCount = 4;
      await pumpMatchesPage(t, d);

      await t.tap(find.text('Create Match'));
      await settle(t);

      expect(
        find.text('FC Elite needs at least 5 players before you can create a '
            'match (currently 4).'),
        findsOneWidget,
      );
    });
  });

  group('Proposing a match', () {
    testWidgets('the dialog shows what the match is worth against THAT team',
        (t) async {
      final stakes = _Stakes();
      await pumpMatchesPage(
        t,
        busyTeam(),
        height: 2600,
        pitchPowerLoader: stakes.call,
      );

      await t.tap(_button('Propose Match').first);
      await settle(t);

      expect(find.text('Propose this match?'), findsOneWidget);
      expect(find.text('Pitch Power at stake'), findsOneWidget);
      expect(find.text('+47'), findsOneWidget);
      expect(find.text('−34'), findsOneWidget);
      expect(find.text("Based on both teams' current Pitch Power."),
          findsOneWidget);
      expect(stakes.asked, [
        (teamId: 'my', matchType: 'ranked', opponentTeamId: 'T-o1'),
      ]);
    });

    testWidgets('and for the kind of match THAT request is', (t) async {
      final stakes = _Stakes();
      await pumpMatchesPage(
        t,
        busyTeam(),
        height: 2600,
        pitchPowerLoader: stakes.call,
      );

      // Keravnos FC asked for a casual match.
      await t.tap(_button('Propose Match').at(1));
      await settle(t);

      expect(stakes.asked, [
        (teamId: 'my', matchType: 'casual', opponentTeamId: 'T-o2'),
      ]);
    });

    testWidgets('sending it proposes the request for the acting team and '
        'reloads', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600, pitchPowerLoader: _Stakes().call);

      await t.tap(_button('Propose Match').first);
      await settle(t);
      await t.tap(_inDialog('Send Proposal'));
      await settle(t);

      expect(d.proposed, hasLength(1));
      expect(d.proposed.single.requestId, 'o1');
      expect(d.proposed.single.teamId, 'my');
      expect(d.proposed.single.venueText, isNull);
      expect(
        find.text('Proposal sent vs Anorthosis. Waiting for their captain to '
            'pick.'),
        findsOneWidget,
      );
      expect(d.callsTo('sent'), 2);
    });

    testWidgets('a venue picked on the map goes along', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600, pitchPowerLoader: _Stakes().call);

      await t.tap(_button('Propose Match').first);
      await settle(t);
      final original = venuePicker;
      addTearDown(() => venuePicker = original);
      venuePicker = (ctx, {required city}) async => const VenuePick(
            'Seaside Pitch',
            VenueLocation(
                placeId: 'p1', lat: 35.0, lng: 33.0, source: 'google'),
          );
      await t.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(VenuePickerField),
      ));
      await settle(t);
      await t.tap(_inDialog('Send Proposal'));
      await settle(t);

      expect(d.proposed.single.venueText, 'Seaside Pitch');
    });

    testWidgets('cancelling proposes nothing', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600, pitchPowerLoader: _Stakes().call);

      await t.tap(_button('Propose Match').first);
      await settle(t);
      await t.tap(_inDialog('Cancel'));
      await settle(t);

      expect(d.proposed, isEmpty);
      expect(find.text('Propose this match?'), findsNothing);
    });

    testWidgets('a team of four cannot propose, and is told how many it has',
        (t) async {
      final d = busyTeam()..memberCount = 4;
      await pumpMatchesPage(t, d, height: 2600, pitchPowerLoader: _Stakes().call);

      await t.tap(_button('Propose Match').first);
      await settle(t);
      await t.tap(_inDialog('Send Proposal'));
      await settle(t);

      expect(d.proposed, isEmpty);
      expect(
        find.text('FC Elite needs at least 5 players before you can propose a '
            'match (currently 4).'),
        findsOneWidget,
      );
    });
  });

  group('Accepting a proposal', () {
    testWidgets('the dialog shows what the match is worth against the team '
        'that proposed', (t) async {
      final stakes = _Stakes();
      await pumpMatchesPage(
        t,
        busyTeam(),
        height: 2600,
        pitchPowerLoader: stakes.call,
      );
      await _openTab(t, 'Activity');

      await t.tap(_button('Accept').first);
      await settle(t);

      expect(find.text('Accept this proposal?'), findsOneWidget);
      expect(find.text('Pitch Power at stake'), findsOneWidget);
      expect(find.text('+47'), findsOneWidget);
      expect(find.text('−34'), findsOneWidget);
      // Their suggested venue is part of what is being accepted.
      expect(find.text('Venue: Seaside Pitch'), findsOneWidget);
      expect(stakes.asked, [
        (teamId: 'my', matchType: 'ranked', opponentTeamId: 'P-p1'),
      ]);
    });

    testWidgets('and for the kind of match the request was', (t) async {
      final stakes = _Stakes();
      final d = busyTeam()
        ..incoming['r2'] = [proposal('p3', 'r2', 'Doxa Katokopias', 1500)];
      await pumpMatchesPage(
        t,
        d,
        height: 2600,
        pitchPowerLoader: stakes.call,
      );
      await _openTab(t, 'Activity');

      // The third Accept button is the one under the casual request.
      await t.tap(_button('Accept').last);
      await settle(t);

      expect(stakes.asked, [
        (teamId: 'my', matchType: 'casual', opponentTeamId: 'P-p3'),
      ]);
    });

    testWidgets('accepting confirms that very proposal and reloads', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600, pitchPowerLoader: _Stakes().call);
      await _openTab(t, 'Activity');

      await t.tap(_button('Accept').first);
      await settle(t);
      await t.tap(_inDialog('Accept'));
      await settle(t);

      expect(d.accepted, ['p1']);
      expect(find.text('Match confirmed vs Omonia 29!'), findsOneWidget);
      expect(d.callsTo('matches'), 2);
    });

    testWidgets('cancelling accepts nothing', (t) async {
      final d = busyTeam();
      await pumpMatchesPage(t, d, height: 2600, pitchPowerLoader: _Stakes().call);
      await _openTab(t, 'Activity');

      await t.tap(_button('Accept').first);
      await settle(t);
      await t.tap(_inDialog('Cancel'));
      await settle(t);

      expect(d.accepted, isEmpty);
      expect(find.text('Accept this proposal?'), findsNothing);
    });
  });

  group('Every size, theme and motion setting', () {
    testWidgets('the narrowest phone with the largest text, dark', (t) async {
      await pumpMatchesPage(
        t,
        busyTeam(),
        width: 320,
        height: 3000,
        textScale: 2,
      );

      await _lookAtEverything(t);

      expect(t.takeException(), isNull);
    });

    testWidgets('the narrowest phone with the largest text, light', (t) async {
      await pumpMatchesPage(
        t,
        busyTeam(),
        width: 320,
        height: 3000,
        textScale: 2,
        dark: false,
      );

      await _lookAtEverything(t);

      expect(t.takeException(), isNull);
    });

    testWidgets('with reduced motion everything still opens and answers',
        (t) async {
      final stakes = _Stakes();
      await pumpMatchesPage(
        t,
        busyTeam(),
        height: 2600,
        disableAnimations: true,
        pitchPowerLoader: stakes.call,
      );

      await _lookAtEverything(t);
      await _openTab(t, 'Activity');
      await _openPill(t, 'Requests');
      await t.tap(_button('Accept').first);
      await settle(t);

      expect(find.text('Pitch Power at stake'), findsOneWidget);
      expect(stakes.asked, hasLength(1));
      expect(t.takeException(), isNull);
    });
  });
}
