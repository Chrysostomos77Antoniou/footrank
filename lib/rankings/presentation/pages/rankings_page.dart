import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/rankings/data/ranking_repository.dart';
import 'package:footrank/rankings/presentation/widgets/player_leaderboard.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/rankings/presentation/widgets/rank_row_parts.dart';
import 'package:footrank/core/theme/app_tokens.dart';

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key});

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> with ThemeRepaintMixin {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rankings',
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.26,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (_tab == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Min. ${RankingRepository.minMatches} matches played to be ranked',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassTabs(
                  index: _tab,
                  tabs: const ['Players', 'Teams'],
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                // Not const: these must rebuild when the page repaints (theme
                // change / tab visit) so their colours update. The leaderboards
                // keep their own cached futures, so this is a UI-only rebuild.
                child: IndexedStack(
                  index: _tab,
                  children: const [
                    PlayerLeaderboard(),
                    _TeamLeaderboard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamLeaderboard extends StatefulWidget {
  const _TeamLeaderboard();

  @override
  State<_TeamLeaderboard> createState() => _TeamLeaderboardState();
}

/// Uses [ThemeRepaintMixin] for the same reason [RankingsPage] and the player
/// leaderboard do: without it this widget never rebuilds on a runtime theme
/// toggle, so every colour it resolved — text included — stays on the previous
/// mode until something else forces a rebuild. This was the last list surface
/// in the app missing it, which is why the Teams sub-tab kept rendering the
/// wrong text colour while Players rendered correctly.
class _TeamLeaderboardState extends State<_TeamLeaderboard>
    with ThemeRepaintMixin {
  final _repo = RankingRepository();
  final _cityCtrl = TextEditingController();
  late Future<List<TeamModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchTeams();
    _cityCtrl.addListener(() => setState(() {}));
    appRefresh.addListener(_applyCity);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_applyCity);
    _cityCtrl.dispose();
    super.dispose();
  }

  void _applyCity() {
    if (!mounted) return;
    setState(() {
      _future = _repo.fetchTeams();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            controller: _cityCtrl,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Search teams by name or city…',
              constraints: const BoxConstraints(minHeight: 52, maxHeight: 52),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _cityCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => _cityCtrl.clear()),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<TeamModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList();
              }
              if (snapshot.hasError) {
                return ErrorView(
                  message: friendlyError(snapshot.error!),
                  onRetry: _applyCity,
                );
              }
              final all = snapshot.data ?? [];
              final q = _cityCtrl.text.trim().toLowerCase();
              final teams = q.isEmpty
                  ? all
                  : all
                      .where((t) =>
                          t.name.toLowerCase().contains(q) ||
                          (t.city ?? '').toLowerCase().contains(q))
                      .toList();
              if (teams.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async => _applyCity(),
                  child: ListView(children: [
                    const SizedBox(height: 80),
                    EmptyView(
                      icon: Icons.shield_outlined,
                      title: q.isEmpty
                          ? 'No ranked teams yet'
                          : 'No teams match "$q"',
                    ),
                  ]),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _applyCity(),
                child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                itemCount: teams.length,
                itemBuilder: (context, i) {
                  final t = teams[i];
                  return FadeSlideIn(
                    delay: AppMotion.staggerFor(i),
                    animateOnceId: t.id,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RankRowCard(
                        onTap: () => showTeamSheet(context, t),
                        child: Row(
                          children: [
                            RankDisc(rank: i + 1),
                            const SizedBox(width: 10),
                            GreenAvatar(name: t.name, imageUrl: t.logoUrl),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Colour comes from the TextTheme, which is
                                  // rebuilt with the ThemeData on every theme
                                  // change, so it follows a runtime toggle.
                                  Text(t.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontSize: 15,
                                              height: 1.25,
                                              letterSpacing: -0.15,
                                              fontWeight: FontWeight.w800)),
                                  Text.rich(
                                    TextSpan(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              fontSize: 12,
                                              height: 1.3,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.muted(context)),
                                      children: [
                                        if (t.city != null)
                                          TextSpan(text: '${t.city!} · '),
                                        TextSpan(
                                          text: t.record,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            PwrScoreBadge(value: t.rating),
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
