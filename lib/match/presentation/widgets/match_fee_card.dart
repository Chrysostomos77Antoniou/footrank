import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/match_payment_model.dart';

/// The captain-facing card for their team's share of the FootRank match fee.
///
/// Deliberately careful about what it claims: FootRank charges its own fee and
/// nothing more — the pitch is still booked and paid for at the venue, in cash,
/// exactly as before. We do not hold venue inventory, so this card must never
/// read as though paying reserves a slot. The "paid at the venue" line is load
/// bearing, not decoration: without it a captain can reasonably assume the €2
/// covered the pitch.
class MatchFeeCard extends StatelessWidget {
  /// Null when no charge has been started for this team yet.
  final MatchPaymentModel? payment;

  /// True while the Stripe sheet is open or the webhook is being awaited.
  final bool paying;

  final VoidCallback onPay;

  const MatchFeeCard({
    super.key,
    required this.payment,
    required this.paying,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = payment?.isPaid ?? false;
    final failed = payment?.hasFailed ?? false;
    final refunded = payment?.isRefunded ?? false;

    // Falls back to the €2 default when there's no row yet: the authoritative
    // amount comes from the server when the charge is created.
    final amount = payment?.amountLabel ??
        MatchPaymentModel.formatAmount(200, 'eur');

    if (paid) {
      return GlassCard(
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: AppIconSize.md,
            ),
            const SizedBox(width: AppSemantic.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Match fee paid',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSemantic.labelGap),
                  Text(
                    'Pitch fees are still paid at the venue.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted(context),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              amount,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                color: AppColors.iconAccent(context),
                size: AppIconSize.md,
              ),
              const SizedBox(width: AppSemantic.iconGap),
              Expanded(
                child: Text(
                  "Your team's match fee",
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                amount,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            refunded
                ? 'This fee was refunded. Pay again to confirm your team for '
                    'this match.'
                : 'Each team pays its own share. The pitch itself is booked and '
                    'paid for at the venue as usual.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.muted(context),
            ),
          ),
          if (failed && payment?.failureReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              payment!.failureReason!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: failed ? 'Try again — $amount' : 'Pay $amount',
            icon: Icons.lock_rounded,
            loading: paying,
            onPressed: onPay,
          ),
        ],
      ),
    );
  }
}
