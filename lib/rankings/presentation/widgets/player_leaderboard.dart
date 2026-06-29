import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/rankings/data/ranking_repository.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';

const _positions = ['Goalkeeper', 'Defender', 'Midfielder', 'Forward'];

class PlayerLeaderboard extends StatefulWidget {
  const PlayerLeaderboard({super.key});

  @override
  State<PlayerLeaderboard> createState() => _PlayerLeaderboardState();
}

class _PlayerLeaderboardState extends State<PlayerLeaderboard> {
  final _repo = RankingRepository();
  final _searchCtrl = TextEditingController();
  String? _position;
  late Future<List<UserModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchPlayers();
    _searchCtrl.addListener(() => setState(() {}));
    appRefresh.addListener(_refresh);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_refresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _repo.fetchPlayers(position: _position));
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search players by name…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchCtrl.clear()),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DropdownButtonFormField<String>(
            value: _position,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Position',
              prefixIcon: Icon(Icons.sports_handball_outlined),
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
                return Center(child: Text('Error: ${snapshot.error}'));
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
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          q.isEmpty
                              ? 'No ranked players yet.\nPlayers appear here after playing 5+ matches.'
                              : 'No players match "$q".',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: players.length,
                itemBuilder: (context, i) {
                  final p = players[i];
                  return FadeSlideIn(
                    delay: Duration(milliseconds: 40 * i),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        onTap: () => showPlayerSheet(context, p),
                        child: Row(
                          children: [
                            RankBadge(rank: i + 1),
                            const SizedBox(width: 10),
                            GradientAvatar(
                                name: p.name,
                                imageUrl: p.avatarUrl,
                                radius: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15.5,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '@${p.username}'
                                    '${p.position != null ? '  ·  ${p.position}' : ''}',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65)),
                                  ),
                                ],
                              ),
                            ),
                            LevelBadge(value: p.elo, size: 46, showLabel: true),
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
