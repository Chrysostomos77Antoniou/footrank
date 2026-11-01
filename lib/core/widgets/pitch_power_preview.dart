import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/team/data/team_repository.dart';

/// The three Pitch Power changes a team stands to get from one match.
typedef PitchPowerDeltas = ({int win, int draw, int loss});

/// Loads the deltas for a team (and, when known, its opponent). Production
/// uses [TeamRepository.previewRatingDelta]; tests pass their own.
typedef PitchPowerLoader = Future<PitchPowerDeltas> Function({
  required String teamId,
  required String matchType,
  String? opponentTeamId,
});

/// Shows the Pitch Power (team rating) a team stands to gain or lose for each
/// possible outcome of its next match, before it's proposed, accepted, or
/// played. The projection comes from a server RPC -- team rating moves
/// independently of player ELO (see apply_elo_on_completion), with a catch-up
/// bonus based on the roster's hidden real skill, and that hidden number is
/// never sent to the client, only the resulting deltas.
///
/// Pass [opponentTeamId] whenever the opponent is known: the real move depends
/// on the rating difference between the two teams (beating a stronger team pays
/// more, losing to a weaker one costs more), so without it the numbers are only
/// the generic base move.
class PitchPowerPreview extends StatefulWidget {
  final String teamId;
  final String? opponentTeamId;
  final String matchType;

  /// When true, renders as a light inset panel without its own card, so it
  /// can sit inside a dialog or a card the caller already draws.
  final bool compact;

  /// Test seam: replaces the server call.
  @visibleForTesting
  final PitchPowerLoader? loader;

  const PitchPowerPreview({
    super.key,
    required this.teamId,
    required this.matchType,
    this.opponentTeamId,
    this.compact = false,
    this.loader,
  });

  @override
  State<PitchPowerPreview> createState() => _PitchPowerPreviewState();
}

class _PitchPowerPreviewState extends State<PitchPowerPreview> {
  late Future<PitchPowerDeltas> _future = _load();

  Future<PitchPowerDeltas> _load() {
    final loader = widget.loader ?? TeamRepository().previewRatingDelta;
    return loader(
      teamId: widget.teamId,
      matchType: widget.matchType,
      opponentTeamId: widget.opponentTeamId,
    );
  }

  @override
  void didUpdateWidget(PitchPowerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId ||
        oldWidget.opponentTeamId != widget.opponentTeamId ||
        oldWidget.matchType != widget.matchType) {
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return FutureBuilder<PitchPowerDeltas>(
      future: _future,
      builder: (context, snapshot) {
        final deltas = snapshot.data;
        // Nothing to show (loading, or the server had no answer): take no room,
        // then ease in once the numbers arrive so the surrounding layout does
        // not jump.
        final Widget child = deltas == null
            ? const SizedBox(width: double.infinity)
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: still ? Duration.zero : AppMotion.enter,
                curve: Curves.easeOut,
                builder: (context, t, child) =>
                    Opacity(opacity: t, child: child),
                child: _Panel(
                  deltas: deltas,
                  hasOpponent: widget.opponentTeamId != null,
                  compact: widget.compact,
                ),
              );
        return MotionSize(child: child);
      },
    );
  }
}

class _Panel extends StatelessWidget {
  final PitchPowerDeltas deltas;
  final bool hasOpponent;
  final bool compact;
  const _Panel({
    required this.deltas,
    required this.hasOpponent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    final divider = Container(
      width: AppSemantic.borderWidth,
      height: AppSpacing.xl,
      color: AppColors.border(context),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.bolt,
                size: AppIconSize.sm, color: AppColors.brand(context)),
            const SizedBox(width: AppSemantic.iconGap),
            Expanded(
              child: Text('Pitch Power at stake',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
                child: _Outcome(
                    label: 'Win',
                    delta: deltas.win,
                    color: AppColors.success)),
            divider,
            Expanded(
                child: _Outcome(
                    label: 'Draw',
                    delta: deltas.draw,
                    color: AppColors.gold)),
            divider,
            Expanded(
                child: _Outcome(
                    label: 'Loss',
                    delta: deltas.loss,
                    color: AppColors.danger)),
          ],
        ),
        if (hasOpponent) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Based on both teams' current Pitch Power.",
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, height: 1.35),
          ),
        ],
      ],
    );

    if (!compact) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm, horizontal: AppSpacing.md),
        child: content,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: content,
    );
  }
}

class _Outcome extends StatelessWidget {
  final String label;
  final int delta;
  final Color color;

  const _Outcome(
      {required this.label, required this.delta, required this.color});

  /// "+47", "0", "−34" (a real minus sign, not a hyphen).
  static String format(int delta) =>
      delta > 0 ? '+$delta' : (delta < 0 ? '−${delta.abs()}' : '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spoken = delta > 0
        ? 'plus $delta points'
        : (delta < 0 ? 'minus ${delta.abs()} points' : 'no change');
    return Semantics(
      label: '$label, $spoken',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.muted(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: AppSemantic.labelGap),
          Text(
            format(delta),
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: AppTypeScale.headline2,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
