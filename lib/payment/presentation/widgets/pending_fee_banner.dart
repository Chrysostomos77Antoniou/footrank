import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/payment/data/payment_repository.dart';
import 'package:footrank/payment/presentation/widgets/pay_fee_button.dart';
import 'package:footrank/routing/app_router.dart';

/// The "what do I do next" prompt on Home for a captain who owes a match fee.
///
/// This exists because the fee card inside the match detail page was not
/// discoverable: a captain had to already know a fee existed, open the right
/// match, and scroll to it. Home is the screen the app opens on, so an
/// outstanding fee belongs here, with the Pay button on the banner itself --
/// paying should not require navigating anywhere.
///
/// Renders nothing at all when there is nothing owed (or payments are disabled
/// in this build), so it costs a captain with no fees due exactly one row of
/// whitespace: none.
class PendingFeeBanner extends StatefulWidget {
  const PendingFeeBanner({super.key});

  @override
  State<PendingFeeBanner> createState() => _PendingFeeBannerState();
}

class _PendingFeeBannerState extends State<PendingFeeBanner> {
  final _repo = PaymentRepository();

  List<PendingFee> _fees = const [];

  @override
  void initState() {
    super.initState();
    _load();
    // A fee becomes due the moment the opponent confirms, which happens while
    // this screen is already open -- so refresh on the same signal every other
    // tab uses rather than only on a cold start.
    appRefresh.addListener(_load);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final fees = await _repo.fetchPendingFees();
    if (mounted) setState(() => _fees = fees);
  }

  @override
  Widget build(BuildContext context) {
    if (_fees.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final brand = AppColors.brand(context);
    // Soonest first (the repository orders by kick-off), so the most urgent fee
    // is the one with the button. Any others are summarised beneath it rather
    // than stacking full-width banners down the home screen.
    final fee = _fees.first;
    final extra = _fees.length - 1;

    final d = fee.scheduledAt.toLocal();
    final when = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')} · '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: FadeSlideIn(
      child: GlassCard(
        tint: brand,
        onTap: () =>
            context.push(AppRoutes.matchDetail, extra: fee.matchId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, color: brand, size: AppIconSize.md),
                const SizedBox(width: AppSemantic.iconGap),
                Expanded(
                  child: Text(
                    fee.previouslyFailed ? 'Payment failed' : 'Action needed',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: brand,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Text(
                  fee.amountLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              fee.fixture,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSemantic.labelGap),
            Text(
              '$when · ${fee.city}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted(context)),
            ),
            const SizedBox(height: AppSemantic.labelGap),
            Text(
              fee.previouslyFailed
                  ? 'Your card was declined. Try again to confirm your team.'
                  : 'Your match is confirmed. Pay your team\'s share to be all '
                      'set — the pitch itself is still paid at the venue.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted(context)),
            ),
            const SizedBox(height: AppSpacing.sm),
            PayFeeButton(fee: fee, onPaid: _load),
            if (extra > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                extra == 1
                    ? '1 more match is awaiting your fee'
                    : '$extra more matches are awaiting your fee',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted(context)),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
