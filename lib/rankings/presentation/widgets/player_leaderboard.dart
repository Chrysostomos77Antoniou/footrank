import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/rankings/data/ranking_repository.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/rankings/presentation/widgets/rank_row_parts.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/team_picker.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/theme/app_tokens.dart';

const _positions = ['Goalkeeper', 'Defender', 'Midfielder', 'Forward'];

class PlayerLeaderboard extends StatefulWidget {
  const PlayerLeaderboard({super.key});

  @override
  State<PlayerLeaderboard> createState() => _PlayerLeaderboardState();
}

/// Uses [ThemeRepaintMixin] like every other screen in the app. This widget
/// was the only list surface without it, so a runtime theme toggle left it
/// painting with the previous mode's colours until something else forced a
/// rebuild.
class _PlayerLeaderboardState extends State<PlayerLeaderboard>
    with ThemeRepaintMixin {
  final _repo = RankingRepository();
  final _teamRepo = TeamRepository();
  final _searchCtrl = TextEditingController();
  String? _position;
  late Future<List<UserModel>> _future;

  // Teams the viewer captains — drives the per-row "invite" button.
  List<TeamModel> _captainTeams = [];
  String? _uid;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchPlayers();
    _uid = SupabaseService.client.auth.currentUser?.id;
    _loadCaptainTeams();
    _searchCtrl.addListener(() => setState(() {}));
    appRefresh.addListener(_refresh);
  }

  Future<void> _loadCaptainTeams() async {
    final teams = await _teamRepo.fetchMyCaptainTeams();
    if (!mounted) return;
    setState(() => _captainTeams = teams);
  }

  Future<void> _invite(UserModel p) async {
    final team = await chooseTeam(context, _captainTeams,
        title: 'Invite ${p.name} to…');
    if (!mounted || team == null) return;
    try {
      await _teamRepo.invitePlayer(teamId: team.id, userId: p.id);
      if (!mounted) return;
      showSuccess(context, 'Invitation sent to ${p.name} for ${team.name}');
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  @override
  void dispose() {
    appRefresh.removeListener(_refresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _repo.fetchPlayers(position: _position);
    });
    _loadCaptainTeams();
  }

  void _setPosition(String? position) {
    setState(() {
      _position = position;
      _future = _repo.fetchPlayers(position: position);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Search players by name…',
              constraints: const BoxConstraints(minHeight: 52, maxHeight: 52),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => _searchCtrl.clear()),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: DropdownButtonFormField<String>(
            value: _position,
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.muted(context)),
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              labelText: 'Position',
              constraints: BoxConstraints(minHeight: 52),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('All positions'),
              ),
              ..._positions.map((p) => DropdownMenuItem(
                  value: p, child: Text(p))),
            ],
            onChanged: _setPosition,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<UserModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList();
              }
              if (snapshot.hasError) {
                return ErrorView(
                  message: friendlyError(snapshot.error!),
                  onRetry: _refresh,
                );
              }
              final all = snapshot.data ?? [];
              final q = _searchCtrl.text.trim().toLowerCase();
              final players = q.isEmpty
                  ? all
                  : all
                      .where((p) =>
                          p.name.toLowerCase().contains(q) ||
                          p.username.toLowerCase().contains(q))
                      .toList();
              if (players.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    children: [
                      const SizedBox(height: 80),
                      EmptyView(
                        icon: Icons.emoji_events_outlined,
                        title: q.isEmpty
                            ? 'No ranked players yet'
                            : 'No players match "$q"',
                        hint: q.isEmpty
                            ? 'Players appear here after playing ${RankingRepository.minMatches}+ matches.'
                            : null,
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                itemCount: players.length,
                itemBuilder: (context, i) {
                  final p = players[i];
                  final isMe = p.id == _uid;
                  return FadeSlideIn(
                    delay: AppMotion.staggerFor(i),
                    animateOnceId: p.id,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RankRowCard(
                        highlight: isMe,
                        onTap: () => showPlayerSheet(context, p),
                        child: Row(
                          children: [
                            RankDisc(rank: i + 1, highlight: isMe),
                            const SizedBox(width: 10),
                            GreenAvatar(name: p.name, imageUrl: p.avatarUrl),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Sourced from the TextTheme (rebuilt with
                                  // the ThemeData) so it follows a runtime
                                  // theme toggle.
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                    fontSize: 15,
                                                    height: 1.25,
                                                    letterSpacing: -0.15,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 6),
                                        const YouTag(),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '@${p.username}'
                                    '${p.position != null ? '  ·  ${p.position}' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            fontSize: 12,
                                            height: 1.3,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.muted(context)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            PwrScoreBadge(value: p.elo),
                            if (_captainTeams.isNotEmpty) ...[
                              // Reserve the button's footprint even when it's
                              // hidden (viewer's own row) so the PWR badge
                              // lands at the same x-position on every row.
                              Visibility(
                                visible: !isMe,
                                maintainSize: true,
                                maintainAnimation: true,
                                maintainState: true,
                                child: IconButton(
                                  tooltip: 'Invite to a team',
                                  icon: Icon(Icons.person_add_alt_1_outlined,
                                      color: AppColors.brand(context)),
                                  onPressed: () => _invite(p),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              );
            },
          ),
        ),
      ],
    );
  }
}
