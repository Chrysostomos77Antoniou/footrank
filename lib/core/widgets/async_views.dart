import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/premium.dart';

/// Consistent loading spinner used across async screens.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ));
}

/// Skeleton placeholder list shown while content loads — feels faster and more
/// premium than a blank spinner. Renders [count] shimmering card rows.
class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  final EdgeInsetsGeometry padding;
  const SkeletonList({
    super.key,
    this.count = 6,
    this.itemHeight = 76,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Row(
        children: [
          ShimmerBox(width: itemHeight * 0.6, height: itemHeight * 0.6, radius: 14),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShimmerBox(width: double.infinity, height: 14, radius: 7),
                const SizedBox(height: 8),
                const ShimmerBox(width: 120, height: 12, radius: 6),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const ShimmerBox(width: 48, height: 28, radius: 9),
        ],
      ),
    );
  }
}

/// Consistent error state with an optional retry.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, this.message = 'Something went wrong', this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent empty state with an icon, title and optional hint/action.
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brand(context).withValues(alpha: 0.10),
              ),
              child: Icon(icon, size: 40, color: AppColors.brand(context)),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: muted)),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
