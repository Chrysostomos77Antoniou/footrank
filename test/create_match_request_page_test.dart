import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/match/presentation/widgets/venue_map_picker.dart';
import 'package:footrank/models/venue_location.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/match/presentation/pages/create_match_request_page.dart';
import 'package:footrank/match/presentation/widgets/venue_widgets.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Records what the form submits instead of calling Supabase.
class _FakeMatchRepository extends MatchRepository {
  _FakeMatchRepository({this.error, this.conflict});

  /// When set, [createMatchRequest] throws it after recording the attempt
  /// (simulates a server-side rejection).
  final Object? error;

  /// When set, the team is reported as already busy at that time.
  final DateTime? conflict;

  final List<Map<String, Object?>> created = [];

  @override
  Future<DateTime?> findSchedulingConflict({
    required String teamId,
    required DateTime scheduledAt,
  }) async =>
      conflict;

  @override
  Future<MatchRequestModel> createMatchRequest({
    required String teamId,
    required String city,
    required DateTime scheduledAt,
    required String matchType,
    required String venueText,
    VenueLocation? venueLocation,
    String format = '5v5',
    List<String>? rosterUserIds,
  }) async {
    created.add({
      'teamId': teamId,
      'city': city,
      'scheduledAt': scheduledAt,
      'matchType': matchType,
      'format': format,
      'venueText': venueText,
      'venueLocation': venueLocation,
      'roster': rosterUserIds,
    });
    final e = error;
    if (e != null) throw e;
    return MatchRequestModel(
      id: 'r1',
      teamId: teamId,
      captainId: 'c1',
      city: city,
      scheduledAt: scheduledAt,
      matchType: matchType,
      format: format,
      status: 'searching',
      createdAt: DateTime(2026, 10, 30),
      venueText: venueText,
    );
  }
}

class _FakeTeamRepository extends TeamRepository {
  @override
  Future<TeamModel> fetchById(String id) async => TeamModel(
        id: id,
        name: 'Keravnos FC',
        city: 'Nicosia',
        captainId: 'c1',
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  Future<List<TeamMemberModel>> fetchMembers(String teamId) async => [
        for (var i = 0; i < 6; i++)
          TeamMemberModel(
            teamId: teamId,
            userId: 'u$i',
            role: i == 0 ? 'captain' : 'player',
            joinedAt: DateTime(2026, 1, 1),
            name: 'Player $i',
            username: 'player$i',
            elo: 1500,
          ),
      ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Opens the Create Match page the way the app does (pushed from another
  /// page, so a successful submit has somewhere to pop back to). [popped]
  /// receives whatever the page returned.
  Future<void> openForm(
    WidgetTester t,
    _FakeMatchRepository repo, {
    List<Object?>? popped,
  }) async {
    final results = popped ?? <Object?>[];
    t.view.physicalSize = const Size(400 * 3, 1600 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async =>
                  results.add(await context.push<MatchRequestModel>('/create')),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/create',
        builder: (_, __) => CreateMatchRequestPage(
          teamId: 't1',
          matchRepository: repo,
          teamRepository: _FakeTeamRepository(),
        ),
      ),
    ]);
    await t.pumpWidget(MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: router,
    ));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  Future<void> submit(WidgetTester t) async {
    final button = find.text('Create Match Request');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
  }

  /// Picks a venue the way a captain does: tap the field, choose on the map.
  /// The map sheet itself is replaced by a fake that returns [name].
  Future<void> typeVenue(WidgetTester t, String name) async {
    final original = venuePicker;
    addTearDown(() => venuePicker = original);
    venuePicker = (ctx, {required city}) async => VenuePick(
          name,
          const VenueLocation(
              placeId: 'p1', lat: 35.1, lng: 33.3, source: 'google'),
        );
    await t.tap(find.byType(VenuePickerField));
    await t.pumpAndSettle();
  }

  group('Create Match: free-text venue', () {
    testWidgets('the venue is chosen on the map, not typed', (t) async {
      await openForm(t, _FakeMatchRepository());

      expect(find.text('Where will you play?'), findsOneWidget);
      expect(find.text('Venue'), findsOneWidget);
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      // No free typing for the venue any more.
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('no venue picked blocks the request before anything is sent',
        (t) async {
      final repo = _FakeMatchRepository();
      await openForm(t, repo);

      await submit(t);

      expect(find.text('Pick the venue on the map'), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('the preview shows the venue picked on the map',
        (t) async {
      await openForm(t, _FakeMatchRepository());

      await typeVenue(t, 'Seaside Pitch');

      final preview = find.byType(VenuePreviewCard);
      expect(
        find.descendant(of: preview, matching: find.text('Seaside Pitch')),
        findsOneWidget,
      );
    });

    testWidgets('submits exactly the cleaned text, with the team and roster',
        (t) async {
      final repo = _FakeMatchRepository();
      final popped = <Object?>[];
      await openForm(t, repo, popped: popped);

      await typeVenue(t, 'Seaside Pitch');
      await submit(t);

      expect(repo.created, hasLength(1));
      final sent = repo.created.single;
      expect(sent['venueText'], 'Seaside Pitch');
      expect(sent['venueLocation'], isNotNull);
      expect(sent['teamId'], 't1');
      expect(sent['city'], 'Nicosia'); // from the team's own city
      expect(sent['matchType'], 'casual');
      expect(sent['format'], '5v5');
      expect(sent['roster'] as List, hasLength(6)); // whole team by default
      expect(
        (sent['scheduledAt'] as DateTime).isAfter(DateTime.now()),
        isTrue,
      );

      // The page closed and handed the new request back to the caller.
      expect(find.text('Create Match'), findsNothing);
      expect(popped, hasLength(1));
      expect((popped.single as MatchRequestModel).venueText, 'Seaside Pitch');
    });

    testWidgets('the typed casing and non-Latin names are kept as written',
        (t) async {
      final repo = _FakeMatchRepository();
      await openForm(t, repo);

      await typeVenue(t, 'ΓΣΠ Αγίου Δομετίου');
      await submit(t);

      expect(repo.created.single['venueText'], 'ΓΣΠ Αγίου Δομετίου');
    });

    testWidgets('a server rejection shows a friendly message and keeps the form',
        (t) async {
      final repo = _FakeMatchRepository(
        error: const PostgrestException(
          message: 'bad_venue:contact',
          code: 'P0001',
        ),
      );
      final popped = <Object?>[];
      await openForm(t, repo, popped: popped);

      await typeVenue(t, 'Call me on pitch');
      await submit(t);

      expect(repo.created.single['venueText'], 'Call me on pitch');
      expect(
        find.text(
            'Enter just the venue name, with no links, emails or phone numbers.'),
        findsOneWidget,
      );
      // Still on the form, nothing handed back, the picked venue is still there.
      expect(find.text('Create Match'), findsOneWidget);
      expect(popped, isEmpty);
      expect(find.text('Call me on pitch'), findsWidgets);
    });

    testWidgets('hitting the daily limit explains it in plain words',
        (t) async {
      final repo = _FakeMatchRepository(
        error: const PostgrestException(
          message: 'daily_limit: max 3 requests per day',
          code: 'P0001',
        ),
      );
      await openForm(t, repo);

      await typeVenue(t, 'Seaside Pitch');
      await submit(t);

      expect(find.text('You can post up to 3 match requests for the same day.'),
          findsOneWidget);
      expect(find.text('Create Match'), findsOneWidget);
    });

    testWidgets('a clash with another commitment is reported before sending',
        (t) async {
      final repo = _FakeMatchRepository(conflict: DateTime(2026, 11, 2, 19));
      await openForm(t, repo);

      await typeVenue(t, 'Seaside Pitch');
      await submit(t);

      expect(repo.created, isEmpty);
      expect(
        find.textContaining('already has an open request or confirmed match'),
        findsOneWidget,
      );
    });
  });
}
