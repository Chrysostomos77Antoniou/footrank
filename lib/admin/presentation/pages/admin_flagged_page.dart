import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/models/flagged_venue_model.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/feedback.dart';

/// Venue names that captains typed which the server could not match to a court
/// with confidence (or that a player reported). The request itself is already
/// published; this is where an admin links it to a court, approves it, or
/// removes it. Players never see the court a name was compared with.
class AdminFlaggedPage extends StatefulWidget {
  /// Injected in widget tests; production uses the real repository.
  final AdminRepository? repo;

  const AdminFlaggedPage({super.key, this.repo});

  @override
  State<AdminFlaggedPage> createState() => _AdminFlaggedPageState();
}

class _AdminFlaggedPageState extends State<AdminFlaggedPage> {
  late final AdminRepository _repo = widget.repo ?? AdminRepository();
  List<FlaggedVenueModel>? _items;
  Object? _error;
  final Set<String> _busy = {};
  List<AdminCourtModel>? _courts;

  @override
  void initState() {
    super.initState();
    _load();
    appRefresh.addListener(_load);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.fetchFlaggedVenues();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _review(
    FlaggedVenueModel v,
    String action, {
    String? courtId,
  }) async {
    setState(() => _busy.add(v.reviewId));
    try {
      await _repo.reviewVenue(v.reviewId, action, courtId: courtId);
      if (!mounted) return;
      setState(() {
        _items = _items?.where((i) => i.reviewId != v.reviewId).toList();
      });
      showSuccess(
        context,
        switch (action) {
          'approve' => 'Approved',
          'link' => 'Linked to the court',
          _ => 'Removed',
        },
      );
      triggerAppRefresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(v.reviewId));
    }
  }

  Future<void> _link(FlaggedVenueModel v) async {
    final List<AdminCourtModel> courts;
    try {
      courts = _courts ??= await _repo.fetchAllCourts();
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final courtId = await showAdminDialog<String>(
      context: context,
      builder: (_) => _LinkCourtDialog(venue: v, courts: courts),
    );
    if (courtId != null) await _review(v, 'link', courtId: courtId);
  }

  Future<void> _remove(FlaggedVenueModel v) async {
    final ok = await showAdminDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this venue?'),
        content: Text(removeVenueMessage(v)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _review(v, 'remove');
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final Widget body;
    final String bodyKey;
    if (items != null) {
      bodyKey = 'content';
      body = items.isEmpty
          ? const Align(
              alignment: Alignment.topCenter,
              child: AdminEmptyState(
                icon: Icons.check_circle_outline,
                message: 'Nothing to review. Every typed venue looks fine.',
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              itemCount: items.length,
              itemBuilder: (context, i) => _FlaggedVenueCard(
                venue: items[i],
                busy: _busy.contains(items[i].reviewId),
                onLink: () => _link(items[i]),
                onApprove: () => _review(items[i], 'approve'),
                onRemove: () => _remove(items[i]),
              ),
            );
    } else if (_error != null) {
      bodyKey = 'error';
      body = Align(
        alignment: Alignment.topCenter,
        child: AdminEmptyState(
          icon: Icons.error_outline,
          message: friendlyError(_error!),
          actionLabel: 'Try again',
          onAction: () {
            setState(() => _error = null);
            _load();
          },
        ),
      );
    } else {
      bodyKey = 'loading';
      body = const AdminTableSkeleton();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminHeader(
          title: 'Flagged venues',
          subtitle:
              'Venue names that matched no court, matched one in another '
              'city, or were reported by a player. Includes venues '
              'suggested in match proposals.',
          action: IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AsyncSwitcher(switcherKey: bodyKey, child: body),
        ),
      ],
    );
  }
}

/// What removing [v] will do, in the words the confirmation dialog shows.
/// Mirrors `admin_review_venue(..., 'remove')`: a name on a match (or on an
/// accepted suggestion) is cleared from the match; a name on an open request
/// deletes the request; a name suggested on a proposal cancels that proposal
/// and leaves the request it was sent to open.
@visibleForTesting
String removeVenueMessage(FlaggedVenueModel v) {
  if (v.matchId != null) {
    return '"${v.venueText}" will be cleared from the match and the '
        'captain asked to enter the real venue name.';
  }
  if (v.isSuggestion) {
    return '"${v.venueText}" was suggested in a match proposal. If the '
        'proposal is still pending it will be cancelled and the team that '
        'sent it notified. The match request it was sent to stays open.';
  }
  if (v.requestStatus == 'searching') {
    return '"${v.venueText}" is on an open match request. The request '
        'will be deleted and the captain notified.';
  }
  return '"${v.venueText}" will be cleared from the match and the '
      'captain asked to enter the real venue name.';
}

/// One flagged venue with its context and the three review actions.
/// Free of network code: it only calls back, so the page above owns all I/O.
class _FlaggedVenueCard extends StatelessWidget {
  final FlaggedVenueModel venue;
  final bool busy;
  final VoidCallback onLink;
  final VoidCallback onApprove;
  final VoidCallback onRemove;

  const _FlaggedVenueCard({
    required this.venue,
    required this.busy,
    required this.onLink,
    required this.onApprove,
    required this.onRemove,
  });

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final v = venue;
    final accent = v.isReported ? AppColors.danger : AppColors.gold;

    final who = [
      if (v.teamName != null && v.teamName!.isNotEmpty) v.teamName!,
      if (v.captainName != null && v.captainName!.isNotEmpty)
        // Any member of a team can propose, so a suggestion's author is not
        // necessarily its captain.
        '${v.isSuggestion ? 'proposed by' : 'captain'} ${v.captainName}',
    ].join(' · ');
    final meta = [
      if (v.isSuggestion)
        v.targetTeamName != null && v.targetTeamName!.isNotEmpty
            ? 'suggested to ${v.targetTeamName}'
            : 'suggested in a proposal',
      if (v.city != null && v.city!.isNotEmpty) v.city!,
      if (v.scheduledAt != null) _fmt(v.scheduledAt!.toLocal()),
      if (v.matchId != null)
        'confirmed match'
      else if (v.requestStatus != null)
        'request ${v.requestStatus}',
    ].join(' · ');
    final closest = v.suggestedCourtName == null
        ? null
        : 'Closest court: ${v.suggestedCourtName}'
              '${v.suggestedCourtCity != null ? ' (${v.suggestedCourtCity})' : ''}'
              '${v.matchScore != null ? ' · ${(v.matchScore! * 100).round()}% similar' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AdminTile(
        accent: accent,
        lit: true,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A Wrap, not a Row: a long name or a large text size drops the
            // reason chip onto its own line instead of overflowing the card.
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  v.venueText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _ReasonChip(label: v.reasonLabel, color: accent),
              ],
            ),
            if (who.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(who, style: theme.textTheme.bodyMedium),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(color: hint),
              ),
            ],
            if (closest != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.link, size: 16, color: hint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      closest,
                      style: theme.textTheme.bodySmall?.copyWith(color: hint),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onLink,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Link to court'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerText(context),
                    side: BorderSide(color: AppColors.dangerText(context)),
                  ),
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final Color color;
  const _ReasonChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSemantic.statusPillRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Picks the court a typed venue name really refers to. Courts in the
/// request's own city come first; the server's closest guess is preselected.
class _LinkCourtDialog extends StatefulWidget {
  final FlaggedVenueModel venue;
  final List<AdminCourtModel> courts;
  const _LinkCourtDialog({required this.venue, required this.courts});

  @override
  State<_LinkCourtDialog> createState() => _LinkCourtDialogState();
}

class _LinkCourtDialogState extends State<_LinkCourtDialog> {
  String? _courtId;
  late final List<AdminCourtModel> _sorted;

  @override
  void initState() {
    super.initState();
    final city = widget.venue.city?.toLowerCase();
    _sorted = [...widget.courts]
      ..sort((a, b) {
        final aSame = a.city.toLowerCase() == city ? 0 : 1;
        final bSame = b.city.toLowerCase() == city ? 0 : 1;
        if (aSame != bSame) return aSame.compareTo(bSame);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final suggested = widget.venue.suggestedCourtId;
    if (suggested != null && _sorted.any((c) => c.id == suggested)) {
      _courtId = suggested;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link to a court'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Players typed: "${widget.venue.venueText}"'),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _courtId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Court'),
              items: [
                for (final c in _sorted)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(
                      '${c.name} · ${c.city}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _courtId = v),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Players never see this link; it is only for your records.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _courtId == null
              ? null
              : () => Navigator.pop(context, _courtId),
          child: const Text('Link'),
        ),
      ],
    );
  }
}
