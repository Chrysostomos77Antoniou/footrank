// Renders every admin page at phone width (390x780) with sample data.
// Overflow and layout errors surface as test failures, so a table that is
// too wide for a phone is caught here instead of in someone's hand.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/models/flagged_venue_model.dart';
import 'package:footrank/admin/presentation/pages/admin_flagged_page.dart';
import 'package:footrank/admin/presentation/pages/admin_courts_page.dart';
import 'package:footrank/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:footrank/admin/presentation/pages/admin_matches_page.dart';
import 'package:footrank/admin/presentation/pages/admin_teams_page.dart';
import 'package:footrank/admin/presentation/pages/admin_users_page.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/admin/models/match_cancellation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime.now();
final teams = [
  for (var i = 0; i < 6; i++)
    TeamModel(
      id: 't$i',
      name: [
        'Keravnos FC',
        'Strovolos United',
        'Limassol Lions',
        'Larnaca Eagles',
        'Aglantzia Boys',
        'Nicosia Titans',
      ][i],
      city: [
        'Nicosia',
        'Nicosia',
        'Limassol',
        'Larnaca',
        'Nicosia',
        'Nicosia',
      ][i],
      captainId: 'c',
      rating: 1700 - i * 40,
      wins: 8 - i,
      losses: i,
      draws: 1,
      createdAt: now,
    ),
];
final users = [
  for (var i = 0; i < 6; i++)
    UserModel(
      id: 'u$i',
      name: [
        'Zacharias Kallis',
        'Yiorgos Antoniou',
        'Yiannis Savva',
        'Xenis Spyrou',
        'Vasilis Pavlou',
        'tomis antoniou',
      ][i],
      username: 'user$i',
      city: i % 3 == 0 ? 'Limassol' : 'Nicosia',
      elo: 1500 + i * 30,
      reliability: i == 0 ? 90 : 100,
      disputeCount: i == 2 ? 2 : 0,
      flagged: i == 2,
      createdAt: now.subtract(Duration(days: i * 20)),
    ),
];
MatchModel m(
  int i, {
  String status = 'completed',
  bool disputed = false,
  int? h,
  int? a,
}) => MatchModel(
  id: 'm$i',
  homeTeamId: 't0',
  awayTeamId: 't1',
  city: 'Nicosia',
  scheduledAt: now.subtract(Duration(days: i)),
  matchType: 'friendly',
  format: '5v5',
  status: status,
  homeScore: h,
  awayScore: a,
  scoreDisputed: disputed,
  createdAt: now,
  homeTeamName: 'Keravnos FC',
  awayTeamName: 'Strovolos United',
  paymentStatus: 'paid',
);
final matches = [
  m(1, h: 3, a: 2),
  m(2, status: 'pending', disputed: true, h: 1, a: 1),
  m(3, status: 'scheduled'),
  m(4, h: 0, a: 4),
];

class FakeRepo extends AdminRepository {
  @override
  Future<List<MatchRequestModel>> fetchAllOpenRequests() async => [];
  @override
  Future<List<MatchProposalModel>> fetchAllPendingProposals() async => [];
  @override
  Future<List<MatchModel>> fetchDisputedMatches() async => [matches[1]];
  @override
  Future<List<UserModel>> fetchFlaggedUsers() async => [users[2]];
  @override
  Future<List<TeamModel>> fetchAllTeams() async => teams;
  @override
  Future<List<AdminCourtModel>> fetchAllCourts() async => courts;
  @override
  Future<List<MatchModel>> fetchAllMatches({
    String? city,
    String? status,
  }) async => matches;
  @override
  Future<List<UserModel>> fetchAllUsers() async => users;
  @override
  Future<List<({DateTime createdAt, int matchesPlayed})>>
  fetchUserGrowth() async => [
    for (final u in users) (createdAt: u.createdAt, matchesPlayed: 3),
  ];
  @override
  Future<List<MatchCancellationModel>> fetchMatchCancellations() async => [];
  @override
  Future<int> fetchFlaggedVenueCount() async => 0;
  @override
  Future<List<FlaggedVenueModel>> fetchFlaggedVenues() async => [];
}

final courts = [
  const AdminCourtModel(
    id: '1',
    name: 'Keravnos 5s',
    city: 'Nicosia',
    active: true,
    hours: '09:00 - 23:00',
    phone: '99 123456',
    address: 'Strovolos',
  ),
  const AdminCourtModel(
    id: '2',
    name: 'Kick On Fives',
    city: 'Nicosia',
    active: false,
  ),
  const AdminCourtModel(
    id: '3',
    name: 'Wembley',
    city: 'Limassol',
    active: true,
    hours: '10:00 - 00:00',
  ),
];

final flagged = [
  FlaggedVenueModel(
    reviewId: 'r1',
    requestId: 'q1',
    venueText: 'Some Rather Long Venue Name Football Center Paphos Harbour',
    reason: 'no_match',
    city: 'Paphos',
    scheduledAt: now.add(const Duration(days: 2)),
    teamName: 'Keravnos FC',
    captainName: 'Andreas Papadopoulos',
    requestStatus: 'searching',
    createdAt: now,
  ),
  FlaggedVenueModel(
    reviewId: 'r2',
    matchId: 'm1',
    venueText: 'Wembley',
    reason: 'reported',
    city: 'Limassol',
    scheduledAt: now.add(const Duration(days: 4)),
    teamName: 'Strovolos United',
    captainName: 'Nikos',
    reportCount: 2,
    suggestedCourtId: '3',
    suggestedCourtName: 'Wembley',
    suggestedCourtCity: 'Limassol',
    matchScore: 0.62,
    createdAt: now,
  ),
];

class FlaggedRepo extends FakeRepo {
  @override
  Future<List<FlaggedVenueModel>> fetchFlaggedVenues() async => flagged;
}

Widget host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.dark,
  home: Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: child,
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> shot(WidgetTester t, String name, Widget w) async {
    t.view.physicalSize = const Size(780, 1560);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(host(w));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // Any RenderFlex overflow or layout error fails the test on its own.
    expect(find.byType(MaterialApp), findsOneWidget, reason: name);
  }

  testWidgets(
    'dash',
    (t) => shot(
      t,
      'dash',
      AdminDashboardPage(onNavigate: (_) {}, repo: FakeRepo()),
    ),
  );
  testWidgets(
    'courts',
    (t) => shot(
      t,
      'courts',
      AdminCourtsView(courts: courts, onEdit: (_) {}, onToggleActive: (_) {}),
    ),
  );
  testWidgets(
    'teams',
    (t) => shot(t, 'teams', AdminTeamsView(teams: teams, onOpen: (_) {})),
  );
  testWidgets(
    'users',
    (t) => shot(t, 'users', AdminUsersPage(repo: FakeRepo())),
  );
  testWidgets(
    'matches',
    (t) => shot(t, 'matches', AdminMatchesPage(repo: FakeRepo())),
  );
  testWidgets('flagged venues', (t) async {
    await shot(t, 'flagged', AdminFlaggedPage(repo: FlaggedRepo()));
    expect(find.text('Flagged venues'), findsOneWidget);
    expect(find.text('Wembley'), findsOneWidget);
    expect(find.text('Link to court'), findsNWidgets(2));
    expect(find.text('Reported by 2 players'), findsOneWidget);
  });
  testWidgets('flagged venues empty', (t) async {
    await shot(t, 'flagged-empty', AdminFlaggedPage(repo: FakeRepo()));
    expect(find.textContaining('Nothing to review'), findsOneWidget);
  });
}
