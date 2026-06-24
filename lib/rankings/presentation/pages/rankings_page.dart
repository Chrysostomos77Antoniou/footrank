import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/rankings/data/ranking_repository.dart';
import 'package:footrank/rankings/presentation/widgets/player_leaderboard.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';

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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const GradientText(
                      'Rankings',
                      style:
                          TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 10),
                    if (_tab == 0)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Min. ${RankingRepository.minMatches} matches played to be ranked',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _GlassTabs(
                  index: _tab,
                  tabs: const ['Players', 'Teams'],
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                // Not const: these must rebuild when the page repaints (theme
                // change / tab visit) so their colours update. The leaderboards
                // keep their own cached futures, so this is a UI-only rebuild.
                child: IndexedStack(
                  index: _tab,
                  children: [
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

class _GlassTabs extends StatelessWidget {
  final int index;
  final List<String> tabs;
  final ValueChanged<int> onChanged;

  const _GlassTabs({
    required this.index,
    required this.tabs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(6),
      radius: 20,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: PressableScale(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == i
                        ? AppColors.iconAccent(context).withValues(alpha: 0.14)
                        : null,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: index == i
                          ? AppColors.iconAccent(context)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamLeaderboard extends StatefulWidget {
  const _TeamLeaderboard();

  @override
  State<_TeamLeaderboard> createState() => _TeamLeaderboardState();
}

class _TeamLeaderboardState extends State<_TeamLeaderboard> {
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _cityCtrl,
            decoration: InputDecoration(
              hintText: 'Search teams by name or city…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _cityCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
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
                  child: ListView(children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No teams found')),
                  ]),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _applyCity(),
                child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: teams.length,
                itemBuilder: (context, i) {
                  final t = teams[i];
                  return FadeSlideIn(
                    delay: Duration(milliseconds: 40 * i),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        onTap: () => showTeamSheet(context, t),
                        child: Row(
                          children: [
                            RankBadge(rank: i + 1),
                            const SizedBox(width: 10),
                            GradientAvatar(
                                name: t.name,
                                imageUrl: t.logoUrl,
                                radius: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15.5,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface)),
                                  const SizedBox(height: 2),
                                  Text.rich(
                                    TextSpan(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.65)),
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
                                  ),
                                ],
                              ),
                            ),
                            LevelBadge(value: t.rating, size: 46, showLabel: true),
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
