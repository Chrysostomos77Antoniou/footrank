import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// Round avatar with the accent ring used across the profile screens: a
/// [ring]-wide accent stroke, an optional [gap] of fill colour inside it, then
/// the photo (or the player's initial when there is none).
class ProfileAvatar extends StatelessWidget {
  final String name;
  final ImageProvider? image;
  final double size;
  final double ring;
  final double gap;
  final double fontSize;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.image,
    this.size = 72,
    this.ring = 3,
    this.gap = 0,
    this.fontSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.brand(context), width: ring),
      ),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.darkElevated : AppColors.lightChip,
          image: image == null
              ? null
              : DecorationImage(image: image!, fit: BoxFit.cover),
        ),
        child: image == null
            ? Text(
                initial,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? Theme.of(context).colorScheme.onSurface
                      : AppColors.limeDeep,
                ),
              )
            : null,
      ),
    );
  }
}
