import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/team/data/team_repository.dart';

class AdminTeamsPage extends StatefulWidget {
  const AdminTeamsPage({super.key});

  @override
  State<AdminTeamsPage> createState() => _AdminTeamsPageState();
}

class _AdminTeamsPageState extends State<AdminTeamsPage> {
  final _repo = AdminRepository();
  late Future<List<TeamModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAllTeams();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeader(
          title: 'Teams',
          subtitle: 'Every active team and its roster.',
        ),
        const SizedBox(height: AppSpacing.xl),
        Expanded(
          child: FutureBuilder<List<TeamModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final teams = snapshot.data!;
              if (teams.isEmpty) {
                return const AdminEmptyState(
                  icon: Icons.shield_outlined,
                  message: 'No teams yet.',
                );
              }
              return FadeSlideIn(
                child: SizedBox(
                  width: double.infinity,
                  child: GlassCard(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: AdminScrollableTable(
                      child: Column(
                        children: [
                          const AdminTableHeader(
                            columns: ['Team', 'City', 'Power', 'Record', ''],
                            flex: [3, 2, 1, 2, 0],
                            fixedWidths: [null, null, null, null, 44],
                          ),
                          for (final t in teams)
                            _TeamRow(
                              team: t,
                              onTap: () => showDialog(
                                context: context,
                                animationStyle: kAdminDialogAnimationStyle,
                                builder: (_) => _TeamDetailDialog(team: t),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  final TeamModel team;
  final VoidCallback onTap;
  const _TeamRow({required this.team, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  GradientAvatar(
                    name: team.name,
                    imageUrl: team.logoUrl,
                    radius: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(team.city ?? '—'),
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: LevelBadge(value: team.rating, size: 26),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(team.record),
              ),
            ),
            // Fixed-width trailing column so the chevron sits in the same
            // pixel position on every row.
            const SizedBox(
              width: 44,
              child: Icon(Icons.chevron_right, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamDetailDialog extends StatelessWidget {
  final TeamModel team;
  const _TeamDetailDialog({required this.team});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  GradientAvatar(
                    name: team.name,
                    imageUrl: team.logoUrl,
                    radius: 26,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          team.city ?? 'No city set',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  LevelBadge(value: team.rating, size: 40, showLabel: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  _MiniStat(label: 'Record', value: team.record),
                  _MiniStat(label: 'Played', value: '${team.played}'),
                  _MiniStat(
                    label: 'Since',
                    value:
                        '${team.createdAt.day}/${team.createdAt.month}/${team.createdAt.year}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Roster',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: SingleChildScrollView(
                  child: FutureBuilder<List<TeamMemberModel>>(
                    future: TeamRepository().fetchMembers(team.id),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(),
                        );
                      }
                      final members = snapshot.data!;
                      if (members.isEmpty) {
                        return Text(
                          'No players yet.',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        );
                      }
                      return Column(
                        children: [
                          for (final m in members)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  GradientAvatar(
                                    name: m.name,
                                    imageUrl: m.avatarUrl,
                                    radius: 16,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          [
                                            m.roleLabel,
                                            if (m.position != null) m.position,
                                          ].join(' · '),
                                          style: Theme.of(context).textTheme.bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context).hintColor,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  LevelBadge(value: m.elo, size: 26),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}
