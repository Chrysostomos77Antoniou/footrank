import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';

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

/// Full-width, brand-colored primary CTA button with the app's press motion
/// (scale + haptic) rather than Material's default ripple. Use for flows that
/// want the branded pill look instead of the themed [FilledButton].
class BrandButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final IconData? icon;

  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final onBrand = AppColors.onBrand(context);
    return PressableScale(
      onTap: loading ? () {} : onPressed,
      child: Container(
        height: 52,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brand(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: loading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: onBrand),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: onBrand),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      style: TextStyle(
                          color: onBrand,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ],
              ),
      ),
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
