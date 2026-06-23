import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// A gradient hero header used at the top of primary screens.
class GradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final double height;

  const GradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.brandGrad(context),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular brand logo badge (soccer ball on gradient).
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGrad(context),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.sports_soccer,
          color: AppColors.onBrand(context), size: size * 0.55),
    );
  }
}

/// Avatar with a deterministic gradient based on the name + initial.
class GradientAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;

  const GradientAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(imageUrl!),
      );
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onSurface.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.border(context)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: onSurface.withValues(alpha: 0.75),
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
