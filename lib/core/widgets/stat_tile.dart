import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';

/// The single stat tile.
///
/// Consolidates SIX implementations that all showed "a number with a label"
/// and disagreed on nearly every parameter:
///
/// | impl                          | padding | number            | tabular |
/// |-------------------------------|---------|-------------------|---------|
/// | profile_page `_StatCard`      | 20 / 12 | Sora 24 w800      | **yes** |
/// | profile_sheets `_Stat`        | 18 / 12 | Sora 18 w900      | no      |
/// | team_page `_MiniStat`         | 18 / 12 | Sora 18 w900      | no      |
/// | admin_widgets `AdminStatCard` | 20 all  | Sora 24 w800, row | no      |
/// | admin_users `_MiniStat`       | none    | Manrope 16 w800   | no      |
/// | admin_teams `_MiniStat`       | none    | Manrope 15 w800   | no      |
///
/// `_StatCard` wins because it was the only one using
/// [FontFeature.tabularFigures] — without it, digits have variable widths, so
/// an animated count visibly jitters as it rolls and columns of numbers fail
/// to align. Tabular figures on every rating, score, rank and time is a design
/// principle for this app, not a preference.
///
/// [AdminStatCard]'s horizontal layout is preserved as [StatTileLayout.row]
/// rather than deleted — the admin dashboard genuinely needs a wider tile.
enum StatTileLayout {
  /// Icon above the number, centred. The default everywhere in the app.
  column,

  /// Icon beside the number, left-aligned. Admin dashboard.
  row,
}

class StatTile extends StatelessWidget {
  final String label;

  /// Pre-formatted display value. Mutually exclusive with [animateTo].
  final String? value;

  /// Integer target that rolls up via [AnimatedCount]. Takes precedence over
  /// [value] when set.
  final int? animateTo;

  final String suffix;
  final IconData? icon;
  final Color? accent;
  final StatTileLayout layout;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    this.value,
    this.animateTo,
    this.suffix = '',
    this.icon,
    this.accent,
    this.layout = StatTileLayout.column,
    this.onTap,
  }) : assert(value != null || animateTo != null,
            'StatTile needs either a value or an animateTo target');

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.iconAccent(context);

    // Tabular figures: fixed-width digits so a rolling count does not jitter
    // and stacked tiles line up.
    final numberStyle = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: AppTypeScale.display3,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: Theme.of(context).colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final labelStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: AppColors.muted(context));

    final number = animateTo != null
        ? AnimatedCount(animateTo!, suffix: suffix, style: numberStyle)
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$value$suffix',
                maxLines: 1, style: numberStyle),
          );

    final semanticsLabel =
        '$label: ${animateTo != null ? '$animateTo$suffix' : '$value$suffix'}';

    return Semantics(
      label: semanticsLabel,
      button: onTap != null,
      excludeSemantics: true,
      child: GlassCard(
        onTap: onTap,
        padding: layout == StatTileLayout.row
            ? const EdgeInsets.all(AppSpacing.lg)
            : const EdgeInsets.symmetric(
                vertical: AppSpacing.lg, horizontal: AppSpacing.sm),
        child: layout == StatTileLayout.row
            ? _rowBody(context, color, number, labelStyle)
            : _columnBody(context, color, number, labelStyle),
      ),
    );
  }

  Widget _columnBody(
      BuildContext context, Color color, Widget number, TextStyle? labelStyle) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 22, color: color),
          const SizedBox(height: AppSpacing.sm),
        ],
        number,
        const SizedBox(height: AppSemantic.labelGap),
        Text(label, textAlign: TextAlign.center, style: labelStyle),
      ],
    );
  }

  Widget _rowBody(
      BuildContext context, Color color, Widget number, TextStyle? labelStyle) {
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
            ),
            child: Icon(icon, size: AppIconSize.md, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              number,
              const SizedBox(height: AppSemantic.labelGap),
              Text(label, style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}
