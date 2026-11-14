// Shared by the Matches screen tests: builders for the models the screens show,
// a few ready-made sets of data, fake repositories that answer from memory, and
// one function that puts the whole page on a phone-sized screen.
//
// Every date is relative to the moment the test runs ("tomorrow at 19:30"),
// because the screens say "Today" and "Tomorrow" and a fixed date would turn
// every test into a time bomb.
import 'package:footrank/models/venue_location.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/widgets/pitch_power_preview.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/match/presentation/pages/matches_page.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/payment/data/payment_repository.dart';
import 'package:footrank/team/data/team_repository.dart';

final DateTime _created = DateTime.now();

/// [days] from today at [hour]:[minute], local time.
DateTime at(int days, int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + days, hour, minute);
}

TeamModel team(String id, String name, int rating, {String city = 'Larnaca'}) =>
    TeamModel(
      id: id,
      name: name,
      city: city,
      captainId: 'cap',
      rating: rating,
      createdAt: _created,
    );

/// An open match request. By default it belongs to another team (`T-<id>`);
/// pass [teamId] for one posted by the acting team.
MatchRequestModel request(
  String id,
  String name,
  int rating, {
  int day = 1,
  int hour = 19,
  String type = 'ranked',
  String? venue,
  String status = 'searching',
  String teamId = '',
}) =>
    MatchRequestModel(
      id: id,
      teamId: teamId.isEmpty ? 'T-$id' : teamId,
      captainId: teamId.isEmpty ? 'x' : 'cap',
      city: 'Larnaca',
      scheduledAt: at(day, hour, 30),
      matchType: type,
      format: '5v5',
      status: status,
      createdAt: _created,
      teamName: name,
      teamRating: rating,
      venueText: venue,
    );

/// A proposal another team made against one of our requests. Its team id is
/// `P-<id>`.
MatchProposalModel proposal(
  String id,
  String requestId,
  String name,
  int rating, {
  String? venue,
}) =>
    MatchProposalModel(
      id: id,
      requestId: requestId,
      proposingTeamId: 'P-$id',
      proposingUserId: 'u',
      status: 'pending',
      createdAt: _created,
      teamName: name,
      teamRating: rating,
      venueText: venue,
    );

/// A proposal our team sent to somebody else's request.
MatchProposalModel sentProposal(
  String id,
  String target,
  int rating, {
  String? venue,
}) =>
    MatchProposalModel(
      id: id,
      requestId: 'r-$id',
      proposingTeamId: 'my',
      proposingUserId: 'u',
      status: 'pending',
      createdAt: _created,
      venueText: venue,
      requestCity: 'Larnaca',
      requestScheduledAt: at(2, 20, 30),
      requestMatchType: 'ranked',
      requestFormat: '5v5',
      targetTeamName: target,
      targetTeamRating: rating,
    );

/// A fixture of our team (`my`, at home) against another one.
MatchModel fixture(
  String id,
  String status, {
  int day = 2,
  int? homeScore,
  int? awayScore,
  String home = 'FC Elite',
  String away = 'Keravnos FC',
  int homeRating = 1700,
  int awayRating = 1690,
  String? venue,
  bool homeConfirmed = false,
  bool awayConfirmed = false,
  String awayId = '',
}) =>
    MatchModel(
      id: id,
      homeTeamId: 'my',
      awayTeamId: awayId.isEmpty ? 'opp-$id' : awayId,
      city: 'Larnaca',
      scheduledAt: at(day, 20, 30),
      matchType: 'ranked',
      format: '5v5',
      status: status,
      homeScore: homeScore,
      awayScore: awayScore,
      homeOk: homeConfirmed,
      awayOk: awayConfirmed,
      createdAt: _created,
      venueText: venue,
      homeTeamName: home,
      awayTeamName: away,
      homeTeamRating: homeRating,
      awayTeamRating: awayRating,
      homeTeamRecord: '5W · 2L',
      awayTeamRecord: '3W · 3L · 1D',
    );

PendingFee feeFor(String matchId, {int day = 2}) => PendingFee(
      matchId: matchId,
      teamId: 'my',
      homeTeamName: 'FC Elite',
      awayTeamName: 'Keravnos FC',
      scheduledAt: at(day, 20, 30),
      city: 'Larnaca',
    );

typedef CityQuery = ({
  String city,
  String excludeTeamId,
  DateTime? date,
  int? timeOfDayMinutes,
  String? matchType,
});

typedef ProposedMatch = ({
  String requestId,
  String teamId,
  List<String>? roster,
  String? venueText,
});

/// What the fake repositories answer, and what they were asked to do.
class MatchesData {
  /// The acting user's teams, the first one selected. They are captain of all
  /// of them ('cap').
  List<TeamModel> teams = [team('my', 'FC Elite', 1700)];
  List<MatchRequestModel> opponents = [];
  List<MatchRequestModel> requests = [];
  Map<String, List<MatchProposalModel>> incoming = {};
  List<MatchProposalModel> sent = [];
  List<MatchModel> matches = [];
  List<PendingFee> fees = [];

  /// How many players each team has (the first is its captain).
  int memberCount = 7;

  /// Answers that never arrive: every list stays on its loading skeleton.
  bool never = false;

  /// The lists that fail instead of answering: any of 'requests', 'matches',
  /// 'opponents', 'incoming', 'sent'.
  final failing = <String>{};

  /// Every fetch, in order, by the same names.
  final calls = <String>[];

  final cityQueries = <CityQuery>[];
  final proposed = <ProposedMatch>[];
  final accepted = <String>[];
  final rejected = <String>[];
  final confirmed = <String>[];
  final cancelledMatches = <String>[];
  final deletedRequests = <String>[];

  int callsTo(String name) => calls.where((c) => c == name).length;
}

class FakeMatchRepository extends MatchRepository {
  FakeMatchRepository(this.d);
  final MatchesData d;

  Future<T> _answer<T>(String name, T value) {
    d.calls.add(name);
    if (d.never) return Completer<T>().future;
    if (d.failing.contains(name)) {
      return Future<T>.error(Exception('$name could not be loaded'));
    }
    return Future<T>.value(value);
  }

  @override
  Future<List<MatchRequestModel>> fetchMyTeamRequests(String teamId) =>
      _answer('requests', d.requests);

  @override
  Future<List<MatchModel>> fetchTeamMatches(String teamId) =>
      _answer('matches', d.matches);

  @override
  Future<List<MatchRequestModel>> fetchCityRequests({
    required String city,
    required String excludeTeamId,
    DateTime? date,
    int? timeOfDayMinutes,
    String? matchType,
  }) {
    d.cityQueries.add((
      city: city,
      excludeTeamId: excludeTeamId,
      date: date,
      timeOfDayMinutes: timeOfDayMinutes,
      matchType: matchType,
    ));
    return _answer('opponents', d.opponents);
  }

  @override
  Future<Map<String, List<MatchProposalModel>>> fetchProposalsForTeamRequests(
          String teamId) =>
      _answer('incoming', d.incoming);

  @override
  Future<List<MatchProposalModel>> fetchSentProposals(String teamId) =>
      _answer('sent', d.sent);

  @override
  Future<String> proposeMatch({
    required String requestId,
    required String teamId,
    List<String>? rosterUserIds,
    String? venueText,
    VenueLocation? venueLocation,
  }) async {
    d.proposed.add((
      requestId: requestId,
      teamId: teamId,
      roster: rosterUserIds,
      venueText: venueText,
    ));
    return 'proposal-1';
  }

  @override
  Future<String> acceptProposal(String proposalId) async {
    d.accepted.add(proposalId);
    return 'match-1';
  }

  @override
  Future<void> rejectProposal(String proposalId) async {
    d.rejected.add(proposalId);
  }

  @override
  Future<String> confirmFixture(String matchId) async {
    d.confirmed.add(matchId);
    return 'confirmed';
  }

  @override
  Future<void> cancelMatch(String matchId) async {
    d.cancelledMatches.add(matchId);
  }

  @override
  Future<void> deleteRequest(String requestId) async {
    d.deletedRequests.add(requestId);
  }
}

class FakeTeamRepository extends TeamRepository {
  FakeTeamRepository(this.d);
  final MatchesData d;

  @override
  Future<List<TeamModel>> fetchMyTeams() async => d.teams;

  @override
  Future<List<TeamMemberModel>> fetchMembers(String teamId) async => [
        for (var i = 0; i < d.memberCount; i++)
          TeamMemberModel(
            teamId: teamId,
            userId: 'u$i',
            role: i == 0 ? 'captain' : 'player',
            joinedAt: _created,
            name: 'Player $i',
            username: 'player$i',
            elo: 1500,
          ),
      ];
}

class FakePaymentRepository extends PaymentRepository {
  FakePaymentRepository(this.d);
  final MatchesData d;

  @override
  Future<List<PendingFee>> fetchPendingFees() async => d.fees;
}

/// A busy team: opponents of every kind, requests with proposals, proposals
/// sent, matches waiting for confirmation, confirmed with a fee due, and played.
MatchesData busyTeam() {
  final d = MatchesData();
  d.opponents = [
    request('o1', 'Anorthosis', 1820, venue: 'Larnaca Stadium'),
    request('o2', 'Keravnos FC', 1690, day: 2, hour: 20, type: 'casual'),
    request('o3', 'AEK Veterans', 1550, day: 3, hour: 21, venue: 'Seaside Pitch'),
    request('o4', 'Strovolos United With A Very Long Name FC', 2100, day: 5),
  ];
  d.requests = [
    request('r1', 'FC Elite', 1700,
        day: 1, hour: 20, venue: 'Home Ground', teamId: 'my'),
    request('r2', 'FC Elite', 1700,
        day: 4, hour: 18, type: 'casual', teamId: 'my'),
  ];
  d.incoming = {
    'r1': [
      proposal('p1', 'r1', 'Omonia 29', 1760, venue: 'Seaside Pitch'),
      proposal('p2', 'r1', 'APOEL Legends', 1590),
    ],
  };
  d.sent = [
    sentProposal('s1', 'Anorthosis', 1820, venue: 'Our pitch behind the school'),
    sentProposal('s2', 'Keravnos FC', 1690),
  ];
  d.matches = [
    fixture('m1', 'confirmed', day: 2, venue: 'Larnaca Stadium'),
    fixture('m2', 'confirmed',
        day: 6, away: 'AEK Veterans', awayRating: 1550),
    fixture('m3', 'pending',
        day: 3, away: 'Omonia 29', awayRating: 1760, homeConfirmed: true),
    fixture('m7', 'pending', day: 5, away: 'Keravnos FC', venue: 'Seaside Pitch'),
    fixture('m4', 'completed', day: -3, homeScore: 4, awayScore: 2),
    fixture('m5', 'completed',
        day: -9,
        homeScore: 1,
        awayScore: 3,
        away: 'Anorthosis',
        awayRating: 1820),
    fixture('m6', 'completed',
        day: -16, homeScore: 2, awayScore: 2, away: 'AEK Veterans'),
  ];
  d.fees = [feeFor('m1')];
  return d;
}

/// Puts the whole Matches page on a phone-sized screen, signed in as [userId]
/// (captain of the fake teams unless you say otherwise), and lets the first
/// answers land. Does not use pumpAndSettle: a page that is still loading
/// shimmers forever.
Future<void> pumpMatchesPage(
  WidgetTester t,
  MatchesData data, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool dark = true,
  bool disableAnimations = false,
  String userId = 'cap',
  PitchPowerLoader? pitchPowerLoader,
}) async {
  t.view.physicalSize = Size(width * 2, height * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: app!,
    ),
    home: MatchesPage(
      matchRepository: FakeMatchRepository(data),
      teamRepository: FakeTeamRepository(data),
      paymentRepository: FakePaymentRepository(data),
      currentUserId: userId,
      pitchPowerLoader: pitchPowerLoader,
    ),
  ));
  await settle(t);
}

/// A second of frames: long enough for answers to land and the entrances of
/// list items to finish, short enough not to wait on endless shimmers.
Future<void> settle(WidgetTester t, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
