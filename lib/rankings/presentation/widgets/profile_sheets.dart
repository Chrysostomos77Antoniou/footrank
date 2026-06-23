import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/emojis.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/team/data/team_repository.dart';

/// Fetches a player's full profile by id and shows the player sheet.
Future<void> showPlayerSheetById(BuildContext context, String userId) async {
  final user = await ProfileRepository().fetchUserById(userId);
  if (user != null && context.mounted) {
    showPlayerSheet(context, user);
  }
}

/// Shows a player's profile in a styled bottom sheet.
void showPlayerSheet(BuildContext context, UserModel user) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _Sheet(child: _PlayerSheet(user: user)),
  );
}

/// Shows a team's profile (+ roster) in a styled bottom sheet.
void showTeamSheet(BuildContext context, TeamModel team) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _Sheet(child: _TeamSheet(team: team)),
  );
}

class _Sheet extends StatelessWidget {
  final Widget child;
  const _Sheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _PlayerSheet extends StatelessWidget {
  final UserModel user;
  const _PlayerSheet({required this.user});

  @override
  Widget build(BuildContext context) {
    final teamRepo = TeamRepository();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand(context), width: 3),
            ),
            child: GradientAvatar(
                name: user.name, imageUrl: user.avatarUrl, radius: 40),
          ),
          const SizedBox(height: 12),
          Text(user.name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          Text('@${user.username}',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6))),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (user.position != null)
                GradientPill(
                    icon: positionIcon(user.position),
                    text: user.position!),
              FutureBuilder<String?>(
                future: teamRepo.fetchUserTeamName(user.id),
                builder: (context, snap) {
                  final team = snap.data;
                  return _MutedChip(
                    icon: Icons.groups,
                    text: team ?? 'Free Agent',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _Stat(
                  icon: Icons.trending_up,
                  value: '${user.elo}',
                  label: 'PWR'),
              const SizedBox(width: 10),
              _Stat(
                  icon: Icons.sports_soccer,
                  value: '${user.matchesPlayed}',
                  label: 'Matches'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Stat(
                  icon: Icons.verified_user_outlined,
                  value: '${user.reliability}%',
                  label: 'Reliability'),
              const SizedBox(width: 10),
              _Stat(
                  icon: Icons.handshake_outlined,
                  value: user.behaviorLabel,
                  label: 'Behavior'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamSheet extends StatelessWidget {
  final TeamModel team;
  const _TeamSheet({required this.team});

  @override
  Widget build(BuildContext context) {
    final teamRepo = TeamRepository();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.brand(context), width: 3),
                  ),
                  child: team.logoUrl != null
                      ? CircleAvatar(
                          radius: 40,
                          backgroundImage: CachedNetworkImageProvider(team.logoUrl!))
                      : GradientAvatar(name: team.name, radius: 40),
                ),
                const SizedBox(height: 12),
                Text(team.name,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900)),
                if (team.city != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.place_outlined,
                          size: 15, color: AppColors.iconAccent(context)),
                      const SizedBox(width: 4),
                      Text(team.city!,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GradientPill(
                        text: 'PWR ${team.rating}', icon: Icons.star),
                    GradientPill(
                        text: team.record, icon: Icons.emoji_events_outlined),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Squad',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          FutureBuilder<List<TeamMemberModel>>(
            future: teamRepo.fetchMembers(team.id),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final members = snap.data ?? [];
              if (members.isEmpty) return const Text('No players yet');
              return Column(
                children: members
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => showPlayerSheetById(context, m.userId),
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                            children: [
                              GradientAvatar(name: m.name, radius: 18),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                      [
                                        if (m.position != null) m.position,
                                        'PWR ${m.elo}'
                                      ].join(' · '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (m.isCaptain)
                                const CaptainArmband(label: 'C')
                              else if (m.isViceCaptain)
                                const CaptainArmband(label: 'VC'),
                            ],
                          ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Stat(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.iconAccent(context).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.iconAccent(context), size: 22),
            ),
            const SizedBox(height: 8),
            GradientText(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MutedChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MutedChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: c, fontSize: 13)),
        ],
      ),
    );
  }
}
