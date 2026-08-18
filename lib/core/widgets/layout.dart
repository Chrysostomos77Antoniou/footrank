import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';

/// A titled section divider, optionally with a trailing action.
///
/// Replaces two incompatible `_SectionLabel` classes plus a scattering of
/// inline `Row(children: [Text(...), Spacer(), TextButton(...)])`.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.muted(context)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A standard list row: leading visual, title, optional subtitle, trailing.
///
/// Replaces two `_CourtRow` classes, two `_NavItem` classes and assorted
/// hand-rolled rows that each picked their own padding and gap.
class AppListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AppListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSemantic.cardPadding),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSemantic.labelGap),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.muted(context)),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A network image that cannot blow up memory.
///
/// Wraps [CachedNetworkImage] and REQUIRES the decode dimensions to be set.
/// Without `memCacheWidth`/`memCacheHeight`, Flutter decodes at the source's
/// natural size: a 4K team logo rendered into a 48px avatar costs ~33MB of
/// RAM instead of ~330KB — a 100x difference, and the fastest way to make a
/// Samsung A70 stutter while scrolling a roster.
class AppNetworkImage extends StatelessWidget {
  final String url;

  /// Logical (dp) size the image will occupy. Decode size is derived from this
  /// and the device pixel ratio.
  final double width;
  final double height;

  final BoxFit fit;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const AppNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: (width * dpr).round(),
      memCacheHeight: (height * dpr).round(),
      fadeInDuration: AppMotion.quick,
      errorWidget: (_, __, ___) =>
          errorWidget ??
          Icon(Icons.image_not_supported_outlined,
              size: AppIconSize.sm, color: AppColors.muted(context)),
      placeholder: (_, __) => ShimmerBox(
        width: width,
        height: height,
        radius: borderRadius?.topLeft.x ?? AppSemantic.controlRadius,
      ),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}
