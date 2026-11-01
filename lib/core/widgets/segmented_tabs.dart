import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/premium.dart';

/// A small solid count pill for things that need the user's attention
/// (proposals waiting, matches to confirm). Solid lime is the app's "look here"
/// colour, so it is kept for counts and the main action and never used as a
/// selected-state fill.
class CountBadge extends StatelessWidget {
  final int count;
  const CountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    // Deliberately not a Container with an alignment: that one stretches to
    // fill whatever width it is offered, so in a Wrap (which offers the whole
    // row) the badge became a bar as wide as the card. Here the number is
    // centred in a box that is exactly as wide as the number needs.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.action,
        borderRadius: BorderRadius.circular(AppSemantic.pill),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.lg,
          minHeight: AppSpacing.lg,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          // A count is a badge, not reading text: it stops growing at 1.2x so
          // it stays a pill at the largest accessibility text sizes.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                count > 99 ? '99+' : '$count',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: AppColors.onAction(context),
                  fontSize: AppTypeScale.label3,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SegmentedTabItem {
  final String label;

  /// Shown as a [CountBadge] when above zero.
  final int badgeCount;
  const SegmentedTabItem(this.label, {this.badgeCount = 0});
}

/// The primary switch of a screen: a few equal segments with a thumb that
/// slides to the selected one.
///
/// Motion, on purpose: the thumb moves (200ms, the standard ease) because it is
/// the one thing that tells you where you went, and the label colour changes in
/// step with it. The content below is NOT animated by this widget -- switching
/// tabs is something people do over and over, and a transition on every switch
/// is just waiting. Under "reduce motion" the thumb jumps.
class SegmentedTabs extends StatelessWidget {
  final int index;
  final List<SegmentedTabItem> items;
  final ValueChanged<int> onChanged;

  const SegmentedTabs({
    super.key,
    required this.index,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.brand(context);
    final n = items.length;
    final selected = index.clamp(0, n - 1);
    // -1 = first segment, +1 = last; a single segment sits in the middle.
    final x = n == 1 ? 0.0 : -1 + 2 * selected / (n - 1);

    return Container(
      height: AppSemantic.minTapTarget,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppSemantic.buttonRadius),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedAlign(
            duration: reduceMotion(context) ? Duration.zero : AppMotion.quick,
            curve: AppMotion.standard,
            alignment: Alignment(x, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: accent.withValues(alpha: 0.45)),
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: _Segment(
                    item: items[i],
                    selected: i == selected,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final SegmentedTabItem item;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppColors.brand(context) : AppColors.muted(context);
    final still = reduceMotion(context);
    final label = item.badgeCount > 0
        ? '${item.label}, ${item.badgeCount}'
        : item.label;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PressableScale(
        onTap: onTap,
        semanticLabel: label,
        child: ExcludeSemantics(
          child: ColoredBox(
            color: Colors.transparent,
            // The segments share the width equally, so a large text size or a
            // narrow phone has to shrink a label, never push it into its
            // neighbour: the text scale is capped at 1.2x and whatever still
            // does not fit scales down, keeping a margin to the thumb's edge.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Center(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: still ? Duration.zero : AppMotion.quick,
                          curve: AppMotion.standard,
                          maxLines: 1,
                          softWrap: false,
                          style: (Theme.of(context).textTheme.labelLarge ??
                                  const TextStyle())
                              .copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                          child: Text(item.label),
                        ),
                        if (item.badgeCount > 0) ...[
                          const SizedBox(width: AppSemantic.iconGap),
                          CountBadge(count: item.badgeCount),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FilterPillItem {
  final String label;

  /// Shown as a [CountBadge] when above zero.
  final int badgeCount;
  const FilterPillItem(this.label, {this.badgeCount = 0});
}

/// A row of pills that choose between a few views of the same list (Open /
/// Sent / Awaiting). Deliberately quieter than [SegmentedTabs]: outlined when
/// idle, a lime tint when chosen, so the two levels never compete.
///
/// Scrolls sideways instead of squeezing, so long labels and large text sizes
/// never get cramped.
class FilterPills extends StatelessWidget {
  final int index;
  final List<FilterPillItem> items;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  const FilterPills({
    super.key,
    required this.index,
    required this.items,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSemantic.screenPadding,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            _Pill(
              item: items[i],
              selected: i == index,
              onTap: () => onChanged(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final FilterPillItem item;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brand(context);
    final muted = AppColors.muted(context);
    final still = reduceMotion(context);
    final duration = still ? Duration.zero : AppMotion.micro;
    final label = item.badgeCount > 0
        ? '${item.label}, ${item.badgeCount}'
        : item.label;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PressableScale(
        onTap: onTap,
        semanticLabel: label,
        // The vertical padding is part of the tap target (48 tall) while the
        // pill itself stays a slimmer 36.
        child: ExcludeSemantics(
          child: ColoredBox(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: AnimatedContainer(
                duration: duration,
                curve: AppMotion.standard,
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.xxl + AppSpacing.xxs,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Same colour at zero alpha when idle, so the tint fades in
                  // instead of passing through a muddy grey.
                  color: accent.withValues(alpha: selected ? 0.14 : 0),
                  borderRadius: BorderRadius.circular(AppSemantic.pill),
                  border: Border.all(
                    color: selected
                        ? accent.withValues(alpha: 0.45)
                        : AppColors.inputBorder(context),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: AppMotion.standard,
                      maxLines: 1,
                      softWrap: false,
                      style: (Theme.of(context).textTheme.labelLarge ??
                              const TextStyle())
                          .copyWith(
                        color: selected ? accent : muted,
                        fontWeight: FontWeight.w700,
                      ),
                      child: Text(item.label),
                    ),
                    if (item.badgeCount > 0) ...[
                      const SizedBox(width: AppSemantic.iconGap),
                      CountBadge(count: item.badgeCount),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
