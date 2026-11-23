import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/models/recruitment_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/recruit/data/recruit_repository.dart';
import 'package:footrank/recruit/presentation/pages/recruit_page.dart';
import 'package:footrank/recruit/presentation/widgets/team_recruit_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _team = TeamModel(id: 't1', name: 'FC Test', captainId: 'u1', createdAt: DateTime(2026));

class _FakeRepo implements RecruitRepository {
  RecruitmentModel? open;
  ({String teamId, int spots, String? position, String? note})? created;

  @override
  Future<RecruitmentModel?> fetchOpenForTeam(String teamId) async => open;

  @override
  Future<void> create({
    required String teamId,
    required int spots,
    String? position,
    String? note,
  }) async {
    created = (teamId: teamId, spots: spots, position: position, note: note);
    open = RecruitmentModel(
        id: 'r1',
        teamId: teamId,
        spots: spots,
        accepted: 0,
        expiresAt: DateTime(2030));
  }

  @override
  Future<void> close(String recruitmentId) async => open = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a post reads its team and counts the spots left', () {
    final p = RecruitmentModel.fromJson({
      'id': 'r1',
      'team_id': 't1',
      'spots': 3,
      'accepted': 1,
      'position': 'Defender',
      'note': null,
      'expires_at': '2030-01-01T00:00:00Z',
      'teams': {
        'id': 't1',
        'name': 'FC Test',
        'city': 'Nicosia',
        'captain_id': 'u1',
        'created_at': '2026-01-01T00:00:00Z',
      },
    });
    expect(p.team?.name, 'FC Test');
    expect(p.spotsLeft, 2);
    expect(spotsText(p), 'Needs 2 players');
  });

  test('a single spot is singular', () {
    final p = RecruitmentModel(
        id: 'r', teamId: 't', spots: 1, accepted: 0, expiresAt: DateTime(2030));
    expect(spotsText(p), 'Needs 1 player');
  });

  test('recruitment server errors read in plain English', () {
    String msg(String code) =>
        friendlyError(PostgrestException(message: code, code: 'P0001'));
    expect(msg('recruit_closed'), 'This team is no longer recruiting.');
    expect(msg('recruit_already_open'),
        'Your team already has an open request for players.');
    expect(msg('duplicate key value violates unique constraint "uq_join_request_recruitment"'),
        'You already asked this team.');
  });

  testWidgets('captain posts a request for 3 players',
      (t) async {
    final repo = _FakeRepo();
    var changed = 0;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: TeamRecruitCard(
            team: _team, repo: repo, onChanged: () => changed++),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('Find players'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('spots-3')));
    await t.tap(find.text('Defender'));
    await t.enterText(find.byKey(const Key('recruit-note')), 'Tuesdays 9pm');
    await t.tap(find.byKey(const Key('recruit-post')));
    await t.pumpAndSettle();

    expect(repo.created?.spots, 3);
    expect(repo.created?.position, 'Defender');
    expect(repo.created?.note, 'Tuesdays 9pm');
    expect(changed, 1);
    expect(find.text('Recruiting now'), findsOneWidget);
    expect(find.text('Needs 3 players'), findsOneWidget);
  });
}
