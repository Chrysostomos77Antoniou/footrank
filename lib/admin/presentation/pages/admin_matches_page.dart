import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
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
  /// Injected in widget tests; production uses the real repository.
  final AdminRepository? repo;

  const AdminMatchesPage({super.key, this.repo});

  @override
  State<AdminMatchesPage> createState() => _AdminMatchesPageState();
}

class _AdminMatchesPageState extends State<AdminMatchesPage>
    with SingleTickerProviderStateMixin {
  late final AdminRepository _repo = widget.repo ?? AdminRepository();
  late final TabController _tabs = TabController(length: 4, vsync: this);

  late Future<List<MatchModel>> _matchesFuture;
  late Future<List<MatchRequestModel>> _requestsFuture;
  late Future<List<MatchProposalModel>> _proposalsFuture;
  late Future<List<MatchCancellationModel>> _cancellationsFuture;

  // Badge counts per tab, filled in as each list loads.
  final List<int?> _counts = List<int?>.filled(4, null);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
    _reload();
    appRefresh.addListener(_reload);
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  void _track<T>(Future<List<T>> f, int slot) {
    f.then((v) {
      if (mounted) setState(() => _counts[slot] = v.length);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    appRefresh.removeListener(_reload);
    _tabs.removeListener(_onTab);
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
    _track(_matchesFuture, 0);
    _track(_requestsFuture, 1);
    _track(_proposalsFuture, 2);
    _track(_cancellationsFuture, 3);
  }

  Future<void> _resolveDispute(MatchModel match) async {
    final result = await showAdminDialog<(int, int)>(
      context: context,
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
    final confirm = await showAdminDialog<bool>(
      context: context,
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
        AdminFilterBar(
          children: [
            for (final (i, label) in const [
              'Matches',
              'Open requests',
              'Pending proposals',
              'Cancellations',
            ].indexed)
              AdminFilterChip(
                label: label,
                count: _counts[i],
                selected: _tabs.index == i,
                // Direct index change: switching sections is a frequent
                // action, so no slide between panes.
                onTap: () => _tabs.index = i,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
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
    return AdminAsyncBody<List<MatchModel>>(
      future: future,
      builder: (context, data) {
        final matches = data;
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
              padding: EdgeInsets.all(
                isAdminPhone(context) ? AppSpacing.xxs : AppSpacing.sm,
              ),
              child: AdminScrollableTable(
                child: Column(
                  children: [
                    if (!isAdminPhone(context))
                      const AdminTableHeader(
                        columns: ['Match', 'City', 'Status', 'Score', ''],
                        flex: [4, 2, 2, 1, 0],
                        fixedWidths: [null, null, null, null, 96],
                      ),
                    for (final m in matches)
                      _MatchRow(
                        compact: isAdminPhone(context),
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
  final bool compact;

  const _MatchRow({
    required this.match,
    required this.onResolveDispute,
    required this.onForceCancel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    if (compact) return _compactCard(context);
    return AdminRowTile(
      tint: match.scoreDisputed ? AppColors.gold.withValues(alpha: 0.07) : null,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _TeamPair(match: match),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${match.homeTeamName ?? '?'} vs ${match.awayTeamName ?? '?'}',
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
                      ).textTheme.labelSmall?.copyWith(color: hint),
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
              child: match.hasScore
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${match.homeScore} - ${match.awayScore}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    )
                  : Text('—', style: TextStyle(color: hint)),
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

String _dm(DateTime d) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final l = d.toLocal();
  return '${l.day} ${m[l.month - 1]} ${l.year}';
}

extension on _MatchRow {
  /// Phone layout: teams + status on the left, score on the right, and the
  /// moderation actions as a labelled row underneath (only when they apply).
  Widget _compactCard(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final canCancel = match.status != 'completed';
    return AdminRowTile(
      tint: match.scoreDisputed ? AppColors.gold.withValues(alpha: 0.07) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _TeamPair(match: match),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${match.homeTeamName ?? '?'} vs ${match.awayTeamName ?? '?'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusChip(
                          status: match.status,
                          disputed: match.scoreDisputed,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${match.city} · ${_dm(match.scheduledAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: hint),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (match.hasScore)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${match.homeScore} - ${match.awayScore}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          if (match.scoreDisputed || canCancel) ...[
            const SizedBox(height: 10),
            // Side by side, equal width, thumb-sized -- never stacked.
            Row(
              children: [
                if (match.scoreDisputed)
                  Expanded(
                    child: _CardAction(
                      icon: Icons.gavel,
                      label: 'Resolve',
                      color: AppColors.gold,
                      onTap: onResolveDispute,
                    ),
                  ),
                if (match.scoreDisputed && canCancel) const SizedBox(width: 8),
                if (canCancel)
                  Expanded(
                    // A lone Cancel stays a quiet half-width button on the
                    // right instead of a full-width bar on every row.
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: match.scoreDisputed ? 1 : 0.5,
                        child: _CardAction(
                          icon: Icons.cancel_outlined,
                          label: 'Cancel match',
                          color: AppColors.danger,
                          onTap: onForceCancel,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small tinted action button -- big enough for a thumb, quiet enough not
/// to shout on every row.
class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdminPressScale(
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            height: 42,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final MatchRequestModel request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return AdminRowTile(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          GradientAvatar(
            name: request.teamName ?? '?',
            imageUrl: request.teamLogo,
            radius: 19,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.teamName ?? 'Unknown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${request.city} · ${request.matchType}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: hint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          LevelBadge(value: request.teamRating ?? 0, size: 26),
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final MatchProposalModel proposal;
  const _ProposalCard({required this.proposal});

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return AdminRowTile(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${proposal.teamName ?? 'Unknown'} → ${proposal.targetTeamName ?? '—'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            proposal.requestCity ?? '—',
            style: TextStyle(fontSize: 12.5, color: hint),
          ),
        ],
      ),
    );
  }
}

class _CancellationCard extends StatelessWidget {
  final MatchCancellationModel item;
  const _CancellationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return AdminRowTile(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.homeTeamName} vs ${item.awayTeamName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Cancelled by ${item.cancelledByTeamName} · ${item.city} · ${_dm(item.createdAt)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: hint),
                ),
              ],
            ),
          ),
          if (item.penalized) ...[
            const SizedBox(width: 8),
            const _PenaltyTag(),
          ],
        ],
      ),
    );
  }
}

class _PenaltyTag extends StatelessWidget {
  const _PenaltyTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Text(
        'Penalty',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.danger,
        ),
      ),
    );
  }
}

/// Two team avatars, the second tucked behind the first.
class _TeamPair extends StatelessWidget {
  final MatchModel match;
  const _TeamPair({required this.match});

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.surface;
    Widget avatar(String? name, String? url) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
      child: GradientAvatar(name: name ?? '?', imageUrl: url, radius: 13),
    );
    return SizedBox(
      width: 46,
      height: 34,
      child: Stack(
        children: [
          Positioned(
            left: 18,
            child: avatar(match.awayTeamName, match.awayTeamLogo),
          ),
          Positioned(
            left: 0,
            child: avatar(match.homeTeamName, match.homeTeamLogo),
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  final Future<List<MatchRequestModel>> future;
  const _RequestsTab({required this.future});

  @override
  Widget build(BuildContext context) {
    return AdminAsyncBody<List<MatchRequestModel>>(
      future: future,
      builder: (context, data) {
        final requests = data;
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
              padding: EdgeInsets.all(
                isAdminPhone(context) ? AppSpacing.xxs : AppSpacing.sm,
              ),
              child: AdminScrollableTable(
                child: Column(
                  children: [
                    if (!isAdminPhone(context))
                      const AdminTableHeader(
                        columns: ['Team', 'City', 'Type', 'Power'],
                        flex: [3, 2, 2, 1],
                      ),
                    for (final r in requests)
                      if (isAdminPhone(context))
                        _RequestCard(request: r)
                      else
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    LevelBadge(
                                      value: r.teamRating ?? 0,
                                      size: 26,
                                    ),
                                  ],
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
    return AdminAsyncBody<List<MatchProposalModel>>(
      future: future,
      builder: (context, data) {
        final proposals = data;
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
              padding: EdgeInsets.all(
                isAdminPhone(context) ? AppSpacing.xxs : AppSpacing.sm,
              ),
              child: AdminScrollableTable(
                child: Column(
                  children: [
                    if (!isAdminPhone(context))
                      const AdminTableHeader(
                        columns: ['Proposing team', 'vs', 'City'],
                        flex: [3, 3, 2],
                      ),
                    for (final p in proposals)
                      if (isAdminPhone(context))
                        _ProposalCard(proposal: p)
                      else
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
    return AdminAsyncBody<List<MatchCancellationModel>>(
      future: future,
      builder: (context, data) {
        final cancellations = data;
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
              padding: EdgeInsets.all(
                isAdminPhone(context) ? AppSpacing.xxs : AppSpacing.sm,
              ),
              child: AdminScrollableTable(
                child: Column(
                  children: [
                    if (!isAdminPhone(context))
                      const AdminTableHeader(
                        columns: [
                          'Match',
                          'Cancelled by',
                          'City',
                          'When',
                          'Penalty',
                        ],
                        flex: [3, 2, 2, 2, 1],
                      ),
                    for (final c in cancellations)
                      if (isAdminPhone(context))
                        _CancellationCard(item: c)
                      else
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
