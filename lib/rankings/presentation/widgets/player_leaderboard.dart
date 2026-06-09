import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
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
  String? _position;
  late Future<List<UserModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchPlayers();
    appRefresh.addListener(_refresh);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_refresh);
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final players = snapshot.data ?? [];
              if (players.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No ranked players yet.\n'
                      'Players appear here after playing 5+ matches.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
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
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                    '@${p.username}'
                                    '${p.position != null ? '  ·  ${p.position}' : ''}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            GradientPill(text: 'PWR ${p.elo}', icon: Icons.bolt),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
