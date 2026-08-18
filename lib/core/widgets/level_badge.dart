import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';

/// Playtomic-style level badge — a compact rounded tile that makes the player's
/// or team's rating (Pitch Power) a focal point. Uses the app's own accent.
///
/// [size] controls the overall scale. [showLabel] adds a small "PWR" caption
/// under the number for the larger, hero variants.
class LevelBadge extends StatelessWidget {
  final int value;
  final double size;
  final bool showLabel;

  /// Roll the number up instead of snapping to it.
  ///
  /// Off by default and deliberately so: this badge appears on every row of a
  /// leaderboard, and forty simultaneous count-ups is decoration, not
  /// feedback. Turn it on where the number is the focal point of the screen —
  /// a profile hero, or the moment a rating changes after a match.
  final bool animate;

  const LevelBadge({
    super.key,
    required this.value,
    this.size = 44,
    this.showLabel = false,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.iconAccent(context);

    // Tabular figures: these ratings stack vertically down a leaderboard, and
    // proportional digits make the columns visibly ragged. They also stop a
    // rolling count from jittering as the digits change width.
    final numberStyle = TextStyle(
      fontFamily: AppFonts.display,
      color: accent,
      fontWeight: FontWeight.w800,
      fontSize: size * 0.34,
      height: 1.05,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      // Grow horizontally so 4-digit ratings fit on one line; never square-clip.
      constraints: BoxConstraints(minWidth: size * 1.25),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size * 0.2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (animate)
            AnimatedCount(value, style: numberStyle)
          else
            Text(
              '$value',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: numberStyle,
            ),
          if (showLabel)
            Text(
              'PWR',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: accent.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
                fontSize: size * 0.16,
                height: 1.1,
                letterSpacing: 0.5,
              ),
            ),
        ],
      ),
    );
  }
}
