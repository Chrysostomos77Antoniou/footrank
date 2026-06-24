import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// Playtomic-style level badge — a compact rounded tile that makes the player's
/// or team's rating (Pitch Power) a focal point. Uses the app's own accent.
///
/// [size] controls the overall scale. [showLabel] adds a small "PWR" caption
/// under the number for the larger, hero variants.
class LevelBadge extends StatelessWidget {
  final int value;
  final double size;
  final bool showLabel;

  const LevelBadge({
    super.key,
    required this.value,
    this.size = 44,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.iconAccent(context);
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
          Text(
            '$value',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontFamily: 'Sora',
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.34,
              height: 1.05,
              letterSpacing: -0.5,
            ),
          ),
          if (showLabel)
            Text(
              'PWR',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'Sora',
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
