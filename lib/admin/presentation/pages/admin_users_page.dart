import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/core/widgets/feedback.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

enum _FilterMode { all, flagged }

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _repo = AdminRepository();
  final _searchCtrl = TextEditingController();
  late Future<List<UserModel>> _future;
  bool _searching = false;
  _FilterMode _filter = _FilterMode.all;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAllUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<UserModel>> _fetchForFilter() => _filter == _FilterMode.all
      ? _repo.fetchAllUsers()
      : _repo.fetchFlaggedUsers();

  void _search(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searching = false;
        _future = _fetchForFilter();
      });
      return;
    }
    setState(() {
      _searching = true;
      _future = _repo.searchUsers(query);
    });
  }

  void _setFilter(_FilterMode mode) {
    setState(() {
      _filter = mode;
      _future = _fetchForFilter();
    });
  }

  Future<void> _openUser(UserModel user) async {
    final changed = await showDialog<bool>(
      context: context,
      animationStyle: kAdminDialogAnimationStyle,
      builder: (_) => _UserDetailDialog(user: user, repo: _repo),
    );
    if (changed == true) {
      setState(() {
        _future = _searching
            ? _repo.searchUsers(_searchCtrl.text)
            : _fetchForFilter();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeader(
          title: 'Users',
          subtitle: 'Search any player, or review flagged accounts.',
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _searchCtrl,
          onChanged: _search,
          decoration: const InputDecoration(
            hintText: 'Search by name or username…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_searching)
          Text(
            'Search results',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          )
        else
          Row(
            children: [
              ChoiceChip(
                label: const Text('All players'),
                selected: _filter == _FilterMode.all,
                onSelected: (_) => _setFilter(_FilterMode.all),
              ),
              const SizedBox(width: AppSpacing.xs),
              ChoiceChip(
                label: const Text('Flagged only'),
                selected: _filter == _FilterMode.flagged,
                onSelected: (_) => _setFilter(_FilterMode.flagged),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: FutureBuilder<List<UserModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = snapshot.data!;
              if (users.isEmpty) {
                final flaggedView =
                    !_searching && _filter == _FilterMode.flagged;
                return AdminEmptyState(
                  icon: _searching
                      ? Icons.search_off
                      : (flaggedView
                            ? Icons.verified_user_outlined
                            : Icons.people_outline),
                  message: _searching
                      ? 'No matching users.'
                      : (flaggedView
                            ? 'No flagged accounts.'
                            : 'No users yet.'),
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
                            columns: [
                              'Player',
                              'Power',
                              'Reliability',
                              'Disputes',
                              '',
                            ],
                            flex: [3, 1, 2, 1, 0],
                            fixedWidths: [null, null, null, null, 44],
                          ),
                          for (final u in users)
                            _UserRow(user: u, onTap: () => _openUser(u)),
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

class _UserRow extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  const _UserRow({required this.user, required this.onTap});

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
                    name: user.name,
                    imageUrl: user.avatarUrl,
                    radius: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '@${user.username}',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  if (user.flagged)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.flag,
                        size: 15,
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: LevelBadge(value: user.elo, size: 26),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${user.reliability}%'),
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${user.disputeCount}'),
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

class _UserDetailDialog extends StatefulWidget {
  final UserModel user;
  final AdminRepository repo;
  const _UserDetailDialog({required this.user, required this.repo});

  @override
  State<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<_UserDetailDialog> {
  late bool _flagged = widget.user.flagged;
  late double _reliability = widget.user.reliability.toDouble();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repo.setUserModeration(
        userId: widget.user.id,
        flagged: _flagged,
        reliability: _reliability.round(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
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
                    name: user.name,
                    imageUrl: user.avatarUrl,
                    radius: 26,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '@${user.username}',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  LevelBadge(value: user.elo, size: 40, showLabel: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  _MiniStat(label: 'Matches', value: '${user.matchesPlayed}'),
                  _MiniStat(label: 'Disputes', value: '${user.disputeCount}'),
                  _MiniStat(
                    label: 'Behavior +',
                    value: '${user.behaviorPositive}',
                  ),
                  _MiniStat(
                    label: 'Behavior -',
                    value: '${user.behaviorNegative}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dispute history',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).hintColor,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      FutureBuilder(
                        future: widget.repo.fetchDisputeHistory(user.id),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            );
                          }
                          final matches = snapshot.data!;
                          if (matches.isEmpty) {
                            return Text(
                              'No disputes on record.',
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (final m in matches)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${m.homeTeamName ?? '?'} vs ${m.awayTeamName ?? '?'}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                                        ),
                                      ),
                                      Text(
                                        m.hasScore
                                            ? '${m.homeScore}-${m.awayScore}'
                                            : 'unresolved',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Flagged'),
                        subtitle: const Text('Marks the account for review'),
                        value: _flagged,
                        onChanged: (v) => setState(() => _flagged = v),
                      ),
                      Text('Reliability: ${_reliability.round()}%'),
                      Slider(
                        value: _reliability,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${_reliability.round()}%',
                        onChanged: (v) => setState(() => _reliability = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
