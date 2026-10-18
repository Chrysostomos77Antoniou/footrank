import 'package:flutter/material.dart';
import 'package:footrank/admin/presentation/widgets/admin_ui.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/premium.dart';

export 'admin_ui.dart';

/// Shared showDialog(...) timing for every dialog in the admin panel.
/// Flutter's own default (confirmed in the SDK source) is a 150ms fade with
/// Curves.easeOut both ways — under the 200-500ms band a modal deserves as
/// an occasional, deliberate interaction. Enter runs longer than exit: the
/// open is the moment being watched, the close is the system getting out of
/// the way.
const kAdminDialogAnimationStyle = AnimationStyle(
  duration: Duration(milliseconds: 220),
  reverseDuration: Duration(milliseconds: 160),
  curve: Curves.easeOut,
  reverseCurve: Curves.easeOut,
);

/// The real app icon (assets/branding/app_icon.png) -- used in place of the
/// generic drawn [BrandLogo] circle throughout the admin panel.
class AdminLogo extends StatelessWidget {
  final double size;
  const AdminLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Page title + optional trailing action, shared across every admin screen
/// for a consistent header rhythm.
class AdminHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const AdminHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GradientText(
                title,
                style: Theme.of(context).textTheme.displayMedium!.copyWith(
                  fontSize: 26,
                  letterSpacing: -0.5,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).hintColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// Glass stat tile with a gradient headline number -- used on the dashboard
/// for at-a-glance counts (open requests, flagged users, disputed matches).
class AdminStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? accent;
  final VoidCallback? onTap;

  /// Position in the dashboard grid -- drives the entrance stagger.
  final int index;

  const AdminStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.accent,
    this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.brand(context);
    return FadeSlideIn(
      delay: AppMotion.staggerFor(index),
      animateOnceId: 'admin-stat-$label',
      offsetY: 8,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            AdminIconChip(icon: icon, color: color, size: 46),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatValue(
                  value,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a table (header + flex-column rows) so it never gets crushed on a
/// narrow phone width -- the table keeps its natural minimum width and
/// scrolls sideways instead of squeezing every column into a sliver.
/// Vertical scrolling still works via the inner [SingleChildScrollView].
class AdminScrollableTable extends StatelessWidget {
  final Widget child;

  const AdminScrollableTable({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT wrapped in a horizontal SingleChildScrollView +
    // ConstrainedBox(minWidth: ...): that combination leaves maxWidth
    // unbounded, and every row here uses Expanded for its columns --
    // Expanded needs a genuinely bounded width to divide proportionally.
    // In debug mode that combination asserts loudly; in release it just
    // silently collapses each row to its minimal content width and lets
    // Column's default center cross-alignment center that shrunken row --
    // exactly the "everything clustered in the middle" bug this replaces.
    // A plain vertical scroll, with the Column stretched to the full
    // (already-guaranteed-bounded, see the SizedBox(width: double.infinity)
    // each caller wraps its GlassCard in) width, gives every row a tight
    // width to divide correctly. The tradeoff: columns get narrower on a
    // small screen instead of scrolling sideways -- each cell already
    // ellipsizes long text, so that's an acceptable simplification.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [child],
      ),
    );
  }
}

/// A row of column headers for the hand-rolled admin tables (plain [Row]s
/// styled to match, rather than [DataTable] -- simpler to keep dense and
/// scrollable at these widths).
class AdminTableHeader extends StatelessWidget {
  final List<String> columns;
  final List<int> flex;

  /// Optional per-column fixed pixel width, matching a row's own fixed-width
  /// trailing columns (e.g. a switch or an edit button) -- null (or a
  /// shorter list) falls back to flex for that column, same as before.
  final List<double?>? fixedWidths;

  const AdminTableHeader({
    super.key,
    required this.columns,
    required this.flex,
    this.fixedWidths,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            _headerCell(
              context,
              fixedWidth: (fixedWidths != null && i < fixedWidths!.length)
                  ? fixedWidths![i]
                  : null,
              flexValue: flex[i],
              label: columns[i],
            ),
        ],
      ),
    );
  }

  Widget _headerCell(
    BuildContext context, {
    required double? fixedWidth,
    required int flexValue,
    required String label,
  }) {
    final text = Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).hintColor,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
    if (fixedWidth != null) {
      return SizedBox(width: fixedWidth, child: text);
    }
    return Expanded(flex: flexValue, child: text);
  }
}

class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  /// Optional recovery action, e.g. "Clear filters".
  final String? actionLabel;
  final VoidCallback? onAction;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: TextStyle(color: Theme.of(context).hintColor)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AdminPressScale(
                child: TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    foregroundColor: AppColors.brand(context),
                  ),
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stat number: counts up the first time it appears when it is an integer
/// (the dashboard's payoff moment), otherwise renders as plain text.
class _StatValue extends StatelessWidget {
  final String value;
  final TextStyle? style;
  const _StatValue(this.value, {this.style});

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(value);
    if (n == null || reduceMotion(context)) return Text(value, style: style);
    return AnimatedCount(n, style: style, duration: AppMotion.count);
  }
}
