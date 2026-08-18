import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/admin/models/match_cancellation_model.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/core/widgets/feedback.dart';

class AdminMatchesPage extends StatefulWidget {
  const AdminMatchesPage({super.key});

  @override
  State<AdminMatchesPage> createState() => _AdminMatchesPageState();
}

class _AdminMatchesPageState extends State<AdminMatchesPage>
    with SingleTickerProviderStateMixin {
  final _repo = AdminRepository();
  late final TabController _tabs = TabController(length: 4, vsync: this);

  late Future<List<MatchModel>> _matchesFuture;
  late Future<List<MatchRequestModel>> _requestsFuture;
  late Future<List<MatchProposalModel>> _proposalsFuture;
  late Future<List<MatchCancellationModel>> _cancellationsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _matchesFuture = _repo.fetchAllMatches();
      _requestsFuture = _repo.fetchAllOpenRequests();
      _proposalsFuture = _repo.fetchAllPendingProposals();
      _cancellationsFuture = _repo.fetchMatchCancellations();
    });
  }

  Future<void> _resolveDispute(MatchModel match) async {
    final result = await showDialog<(int, int)>(
      context: context,
      animationStyle: kAdminDialogAnimationStyle,
      builder: (_) => _ResolveDisputeDialog(match: match),
    );
    if (result == null) return;
    try {
      await _repo.resolveDispute(
        matchId: match.id,
        homeScore: result.$1,
        awayScore: result.$2,
      );
      _reload();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  Future<void> _forceCancel(MatchModel match) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      animationStyle: kAdminDialogAnimationStyle,
      builder: (ctx) => AlertDialog(
        title: const Text('Force-cancel this match?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${match.homeTeamName ?? '?'} vs ${match.awayTeamName ?? '?'}',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (sent to both captains)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Cancel match'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.forceCancelMatch(match.id, reason: reasonCtrl.text.trim());
      _reload();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeader(
          title: 'Matches',
          subtitle: 'Every match, open request, and pending proposal.',
        ),
        const SizedBox(height: AppSpacing.md),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Matches'),
            Tab(text: 'Open requests'),
            Tab(text: 'Pending proposals'),
            Tab(text: 'Cancellations'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _MatchesTab(
                future: _matchesFuture,
                onResolveDispute: _resolveDispute,
                onForceCancel: _forceCancel,
              ),
              _RequestsTab(future: _requestsFuture),
              _ProposalsTab(future: _proposalsFuture),
              _CancellationsTab(future: _cancellationsFuture),
            ],
          ),
        ),
      ],
    );
  }
}

class _MatchesTab extends StatelessWidget {
  final Future<List<MatchModel>> future;
  final ValueChanged<MatchModel> onResolveDispute;
  final ValueChanged<MatchModel> onForceCancel;

  const _MatchesTab({
    required this.future,
    required this.onResolveDispute,
    required this.onForceCancel,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MatchModel>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matches = snapshot.data!;
        if (matches.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.sports_soccer_outlined,
            message: 'No matches yet.',
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
                      columns: ['Match', 'City', 'Status', 'Score', ''],
                      flex: [4, 2, 2, 1, 0],
                      fixedWidths: [null, null, null, null, 96],
                    ),
                    for (final m in matches)
                      _MatchRow(
                        match: m,
                        onResolveDispute: () => onResolveDispute(m),
                        onForceCancel: () => onForceCancel(m),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MatchRow extends StatelessWidget {
  final MatchModel match;
  final VoidCallback onResolveDispute;
  final VoidCallback onForceCancel;

  const _MatchRow({
    required this.match,
    required this.onResolveDispute,
    required this.onForceCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '${match.homeTeamName ?? '?'} vs ${match.awayTeamName ?? '?'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(match.city),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusChip(
                    status: match.status,
                    disputed: match.scoreDisputed,
                  ),
                  if (match.status == 'cancelled' &&
                      match.cancelReason == 'expired_no_score') ...[
                    const SizedBox(height: 2),
                    Text(
                      'No score submitted',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                match.hasScore ? '${match.homeScore}-${match.awayScore}' : '—',
              ),
            ),
          ),
          // Fixed-width trailing column (not flex-proportional) so the
          // action icons sit in the same pixel position on every row,
          // regardless of how many of them show for a given match.
          SizedBox(
            width: 96,
            child: Row(
              children: [
                if (match.scoreDisputed)
                  IconButton(
                    tooltip: 'Resolve dispute',
                    icon: const Icon(
                      Icons.gavel,
                      size: 18,
                      color: AppColors.gold,
                    ),
                    onPressed: onResolveDispute,
                  ),
                if (match.status != 'completed')
                  IconButton(
                    tooltip: 'Force-cancel',
                    icon: const Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    onPressed: onForceCancel,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool disputed;
  const _StatusChip({required this.status, required this.disputed});

  @override
  Widget build(BuildContext context) {
    final label = disputed ? 'disputed' : status;
    final color = disputed
        ? AppColors.gold
        : status == 'completed'
        ? AppColors.success
        : Theme.of(context).hintColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  final Future<List<MatchRequestModel>> future;
  const _RequestsTab({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MatchRequestModel>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.person_search_outlined,
            message: 'No open requests.',
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
                      columns: ['Team', 'City', 'Type', 'Power'],
                      flex: [3, 2, 2, 1],
                    ),
                    for (final r in requests)
                      Padding(
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
                                    name: r.teamName ?? '?',
                                    imageUrl: r.teamLogo,
                                    radius: 14,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(r.teamName ?? 'Unknown'),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(r.city),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(r.matchType),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: LevelBadge(
                                  value: r.teamRating ?? 0,
                                  size: 26,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProposalsTab extends StatelessWidget {
  final Future<List<MatchProposalModel>> future;
  const _ProposalsTab({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MatchProposalModel>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final proposals = snapshot.data!;
        if (proposals.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.pending_actions_outlined,
            message: 'No pending proposals.',
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
                      columns: ['Proposing team', 'vs', 'City'],
                      flex: [3, 3, 2],
                    ),
                    for (final p in proposals)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(p.teamName ?? 'Unknown'),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(p.targetTeamName ?? '—'),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(p.requestCity ?? '—'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Log of captain-initiated cancellations -- these never appear as rows in
/// the Matches tab since `cancel_match`/`cancel_confirmed_match` delete the
/// underlying `matches` row (frees the slot for the "no overlapping
/// commitment" check). This is the only place that event is recorded.
class _CancellationsTab extends StatelessWidget {
  final Future<List<MatchCancellationModel>> future;
  const _CancellationsTab({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MatchCancellationModel>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cancellations = snapshot.data!;
        if (cancellations.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.event_busy_outlined,
            message: 'No captain-cancelled matches.',
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
                      columns: ['Match', 'Cancelled by', 'City', 'When', 'Penalty'],
                      flex: [3, 2, 2, 2, 1],
                    ),
                    for (final c in cancellations)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                '${c.homeTeamName} vs ${c.awayTeamName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                c.cancelledByTeamName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(c.city),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${c.createdAt.day}/${c.createdAt.month}/${c.createdAt.year}',
                                  style: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: c.penalized
                                    ? const Icon(
                                        Icons.remove_circle_outline,
                                        size: 16,
                                        color: AppColors.danger,
                                      )
                                    : Text(
                                        '—',
                                        style: TextStyle(
                                          color: Theme.of(context).hintColor,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResolveDisputeDialog extends StatefulWidget {
  final MatchModel match;
  const _ResolveDisputeDialog({required this.match});

  @override
  State<_ResolveDisputeDialog> createState() => _ResolveDisputeDialogState();
}

class _ResolveDisputeDialogState extends State<_ResolveDisputeDialog> {
  late final _home = TextEditingController(
    text: widget.match.homeReportH?.toString() ?? '',
  );
  late final _away = TextEditingController(
    text: widget.match.awayReportH?.toString() ?? '',
  );

  @override
  void dispose() {
    _home.dispose();
    _away.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return AlertDialog(
      title: const Text('Resolve score dispute'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${m.homeTeamName ?? 'Home'} reported: '
            '${m.homeReportH ?? '?'}-${m.homeReportA ?? '?'}',
          ),
          Text(
            '${m.awayTeamName ?? 'Away'} reported: '
            '${m.awayReportH ?? '?'}-${m.awayReportA ?? '?'}',
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Final score:'),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _home,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: m.homeTeamName ?? 'Home',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _away,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: m.awayTeamName ?? 'Away',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final h = int.tryParse(_home.text.trim());
            final a = int.tryParse(_away.text.trim());
            if (h == null || a == null) return;
            Navigator.pop(context, (h, a));
          },
          child: const Text('Confirm final score'),
        ),
      ],
    );
  }
}
