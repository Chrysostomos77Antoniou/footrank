import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/models/match_payment_model.dart';
import 'package:footrank/payment/data/payment_repository.dart';

/// Pays one team's match fee, from wherever the captain happens to be.
///
/// Shared by the Home prompt and the match list card so a captain can settle a
/// fee without navigating into the match at all. Keeping the flow in one widget
/// means the toasts, the cancel handling and the wait-for-webhook behave
/// identically everywhere -- there is no "the list one behaves differently".
class PayFeeButton extends StatefulWidget {
  final PendingFee fee;

  /// Called after a successful payment, once the webhook has been waited for.
  /// Lets the host refresh whatever it renders from.
  final VoidCallback? onPaid;

  /// Full-width primary (Home) vs compact secondary (inside a list card).
  final bool compact;

  const PayFeeButton({
    super.key,
    required this.fee,
    this.onPaid,
    this.compact = false,
  });

  @override
  State<PayFeeButton> createState() => _PayFeeButtonState();
}

class _PayFeeButtonState extends State<PayFeeButton> {
  final _repo = PaymentRepository();
  bool _paying = false;

  Future<void> _pay() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final result = await _repo.payMatchFee(widget.fee.matchId);
      if (!mounted) return;

      // Backing out of the sheet is a normal thing to do, not an error.
      if (result.isCancelled) return;

      if (result.outcome == PaymentOutcome.failed) {
        showError(context, paymentResultMessage(result));
        widget.onPaid?.call();
        return;
      }

      // Wait for Stripe's webhook so the prompt disappears because the fee is
      // genuinely recorded, not because we assumed it was.
      await _repo.awaitConfirmation(
        matchId: widget.fee.matchId,
        teamId: widget.fee.teamId,
      );
      if (!mounted) return;

      showSuccess(context, paymentResultMessage(result));
      widget.onPaid?.call();
      // Other screens render the same fee state; let them re-fetch.
      triggerAppRefresh();
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = widget.fee.previouslyFailed;
    final amount = widget.fee.amountLabel;
    return AppButton(
      label: failed
          ? 'Try again — $amount'
          : (widget.compact ? 'Pay $amount' : 'Pay $amount now'),
      icon: Icons.lock_rounded,
      loading: _paying,
      variant: widget.compact ? AppButtonVariant.secondary : AppButtonVariant.primary,
      fullWidth: !widget.compact,
      onPressed: _pay,
    );
  }
}
