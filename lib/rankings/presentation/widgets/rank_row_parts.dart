import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';

/// Presentation pieces shared by the Ranks lists and the Free Agents cards, so
/// a player reads the same everywhere: rank disc, green avatar, PWR badge.

/// 34px rank disc. Top three get medal gradients with ink text; everything
/// else is a quiet chip. [highlight] (the viewer's own row) is lime.
class RankDisc extends StatelessWidget {
  final int rank;
  final bool highlight;
  const RankDisc({super.key, required this.rank, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = switch (rank) {
      1 => const [Color(0xFFF7DA7A), Color(0xFFE0A82E)],
      2 => const [Color(0xFFE4E9EE), Color(0xFFA9B3BD)],
      3 => const [Color(0xFFE0A26E), Color(0xFFB87333)],
      _ => null,
    };
    final ink = isDark ? AppColors.navy : AppColors.ink;

    Color? fill;
    Color textColor;
    if (gradient != null && !highlight) {
      textColor = ink;
    } else if (highlight) {
      fill = AppColors.action;
      textColor = ink;
    } else {
      fill = AppColors.chip(context);
      textColor = AppColors.onChip(context);
    }

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: gradient != null && !highlight ? null : fill,
        gradient: gradient != null && !highlight
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient)
            : null,
      ),
      child: Text(
        '$rank',
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: rank < 10 ? 15 : 14,
          fontWeight: FontWeight.w800,
          color: textColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Deep-green initial avatar (photo when available).
class GreenAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  const GreenAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: CachedNetworkImageProvider(imageUrl!),
      );
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.heroDarkA : AppColors.limeDeep,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          color: isDark ? AppColors.darkOnSurface : Colors.white,
        ),
      ),
    );
  }
}

/// The PWR score tile: lime-washed in dark, pale-lime with deep green in light.
class PwrScoreBadge extends StatelessWidget {
  final int value;
  final double height;
  final double minWidth;

  const PwrScoreBadge({
    super.key,
    required this.value,
    this.height = 46,
    this.minWidth = 58,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppColors.brand(context);
    final compact = height < 46;
    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      height: height,
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.lime.withValues(alpha: compact ? 0.14 : 0.12)
            : AppColors.lightChip,
        borderRadius: BorderRadius.circular(compact ? 11 : 12),
        border: Border.all(
          color: isDark
              ? AppColors.lime.withValues(alpha: compact ? 0.45 : 0.4)
              : AppColors.limeDeep.withValues(alpha: compact ? 0.4 : 0.35),
          width: 1.3,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 15,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            'PWR',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: compact ? 9 : 10,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: compact ? 0.9 : 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable 64px leaderboard row surface. [highlight] marks the viewer's own
/// row with a 1.5px accent outline and a faint wash.
class RankRowCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool highlight;

  const RankRowCard({
    super.key,
    required this.child,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.darkCard : AppColors.lightCard;
    final fill = !highlight
        ? base
        : isDark
            ? Color.alphaBlend(AppColors.lime.withValues(alpha: 0.09), base)
            : const Color(0xFFF3FAD9);
    final borderColor = highlight
        ? (isDark ? AppColors.lime : AppColors.limeDeep)
        : AppColors.border(context);

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
          border: Border.all(color: borderColor, width: highlight ? 1.5 : 1),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: highlight ? 61 : 62),
          child: child,
        ),
      ),
    );
  }
}

/// "YOU" tag shown on the viewer's own row.
class YouTag extends StatelessWidget {
  const YouTag({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? AppColors.lime : AppColors.limeDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'YOU',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: isDark ? AppColors.navy : Colors.white,
        ),
      ),
    );
  }
}
