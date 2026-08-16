import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/team/data/team_repository.dart';

/// Shows the Pitch Power (team rating) a team stands to gain or lose for
/// each possible outcome of its next match, before it's proposed, accepted,
/// or played. The projection comes from a server RPC -- team rating now
/// moves independently of player ELO (see apply_elo_on_completion), with a
/// catch-up bonus based on the roster's hidden real skill, and that hidden
/// number is never sent to the client, only the resulting deltas.
class PitchPowerPreview extends StatefulWidget {
  final String teamId;
  final String matchType;

  /// When true, renders without its own card background/border, so it can
  /// be embedded inside a card the caller already draws (e.g. an opponent
  /// or proposal card) instead of nesting cards.
  final bool compact;

  const PitchPowerPreview({
    super.key,
    required this.teamId,
    required this.matchType,
    this.compact = false,
  });

  @override
  State<PitchPowerPreview> createState() => _PitchPowerPreviewState();
}

class _PitchPowerPreviewState extends State<PitchPowerPreview> {
  late Future<({int win, int draw, int loss})> _future;

  @override
  void initState() {
    super.initState();
    _future = TeamRepository().previewRatingDelta(
        teamId: widget.teamId, matchType: widget.matchType);
  }

  @override
  void didUpdateWidget(PitchPowerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId ||
        oldWidget.matchType != widget.matchType) {
      _future = TeamRepository().previewRatingDelta(
          teamId: widget.teamId, matchType: widget.matchType);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({int win, int draw, int loss})>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final deltas = snapshot.data!;

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, size: 18, color: AppColors.lime),
                const SizedBox(width: 6),
                Text('Pitch Power at stake',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Outcome(
                    label: 'Win',
                    delta: deltas.win,
                    color: AppColors.success),
                _Outcome(
                    label: 'Draw',
                    delta: deltas.draw,
                    color: AppColors.gold),
                _Outcome(
                    label: 'Loss',
                    delta: deltas.loss,
                    color: AppColors.danger),
              ],
            ),
          ],
        );

        if (widget.compact) return content;

        return GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: content,
        );
      },
    );
  }
}

class _Outcome extends StatelessWidget {
  final String label;
  final int delta;
  final Color color;

  const _Outcome({required this.label, required this.delta, required this.color});

  @override
  Widget build(BuildContext context) {
    final sign = delta > 0 ? '+' : '';
    return Column(
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).hintColor)),
        const SizedBox(height: 2),
        Text('$sign$delta',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                )),
      ],
    );
  }
}
