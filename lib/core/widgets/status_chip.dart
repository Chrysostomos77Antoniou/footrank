import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/models/match_status.dart';

/// The single status pill for a match's lifecycle state.
///
/// Replaces two classes both named `_StatusChip` that rendered the SAME match
/// state differently depending on which screen you were looking at:
///
/// | state     | admin_matches_page:330      | match_detail_page:880              |
/// |-----------|-----------------------------|------------------------------------|
/// | completed | `AppColors.success` (green) | `colorScheme.tertiary` (pale teal) |
/// | confirmed | `hintColor` (grey)          | `colorScheme.primary` (brand lime) |
/// | disputed  | `AppColors.gold`            | **no branch — showed "Completed"** |
///
/// Three things were wrong beyond the inconsistency:
///
/// 1. **A disputed match displayed a calm "Completed"** on the detail page —
///    the exact screen a captain visits to raise the dispute. That is a
///    correctness bug, not a styling one, and it is the reason this widget
///    takes [disputed] as a required-by-convention flag rather than inferring
///    state from the enum alone (`MatchStatus` has no disputed member; it is a
///    separate column on the match).
/// 2. `colorScheme.tertiary` is not a semantic choice. It is never overridden
///    in `app_theme.dart`, so it is whatever `ColorScheme.fromSeed` emits from
///    the lime seed (#A1D0C5 dark / #39656D light) and would shift silently if
///    anyone changed the seed.
/// 3. A confirmed match was the quietest thing on the admin list and the
///    loudest thing on its own page.
///
/// Colour now derives from the enum only, so the same state cannot render two
/// ways again.
class StatusChip extends StatelessWidget {
  final MatchStatus status;

  /// Disputed outranks the lifecycle state: a completed-but-disputed match
  /// must never read as settled.
  final bool disputed;

  const StatusChip({super.key, required this.status, this.disputed = false});

  /// Convenience for the admin screens, which hold the raw DB string.
  factory StatusChip.fromString(String value, {bool disputed = false}) =>
      StatusChip(status: MatchStatus.fromString(value), disputed: disputed);

  Color _color(BuildContext context) {
    if (disputed) return AppColors.gold;
    return switch (status) {
      MatchStatus.completed => AppColors.success,
      MatchStatus.confirmed => AppColors.iconAccent(context),
      // Not yet real: an open request is genuinely lower-status than a
      // confirmed fixture, and should look it.
      MatchStatus.searching || MatchStatus.pending => AppColors.muted(context),
    };
  }

  String get _label => disputed ? 'Disputed' : status.label;

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Semantics(
      label: 'Match status: $_label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppSemantic.statusPillRadius),
        ),
        child: Text(
          _label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
