import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// Team crest used across the Match feature.
///
/// Shows the team logo when there is one, otherwise a flat monogram:
///  * default: a solid green disc with a light initial (list rows);
///  * [ring]: a neutral disc with a lime / deep-green ring and two-letter
///    monogram (the match header).
class MatchTeamAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;

  /// Draws the accent ring + two-letter monogram variant.
  final bool ring;

  const MatchTeamAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 22,
    this.ring = false,
  });

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (!ring) return parts.first[0].toUpperCase();
    if (parts.length == 1) {
      final p = parts.first;
      return p.substring(0, p.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final accent = AppColors.brand(context);

    final Color fill;
    final Color onFill;
    if (ring) {
      fill = isDark ? AppColors.darkElevated : AppColors.lightChip;
      onFill = isDark ? AppColors.darkOnSurface : AppColors.limeDeep;
    } else {
      fill = isDark ? AppColors.heroDarkA : AppColors.limeDeep;
      onFill = isDark ? AppColors.darkOnSurface : Colors.white;
    }

    final size = radius * 2;
    final Widget disc = hasImage
        ? CircleAvatar(
            radius: radius,
            backgroundColor: fill,
            backgroundImage: CachedNetworkImageProvider(imageUrl!),
          )
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Text(
              _initials,
              style: TextStyle(
                color: onFill,
                fontWeight: FontWeight.w800,
                fontSize: radius * (ring ? 0.72 : 0.78),
                height: 1,
              ),
            ),
          );

    if (!ring) return disc;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 2.5),
      ),
      child: disc,
    );
  }
}
