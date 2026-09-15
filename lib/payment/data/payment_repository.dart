import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:footrank/core/constants/app_constants.dart';
import 'package:footrank/models/match_payment_model.dart';
import 'package:footrank/services/supabase_service.dart';

/// The €2 platform fee one team owes for a confirmed match.
///
/// FootRank never handles the pitch rental — teams pay the venue directly, in
/// cash. This repository only moves our own fee, which is why there's no Stripe
/// Connect, no venue onboarding and nobody to pay out to.
///
/// The amount is deliberately NOT sent to the server: `create-match-payment`
/// computes it from its own MATCH_FEE_CENTS, so a tampered client can't pay a
/// cent. Likewise, nothing here may mark a payment succeeded — only Stripe's
/// webhook can write that, so [fetchMyPayment] is the source of truth.
class PaymentRepository {
  static const _table = 'match_payments';
  static const _createFn = 'create-match-payment';

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// Whether payments are configured in this build at all. False in local/dev
  /// builds with no --dart-define, which is what keeps the "Pay" UI hidden
  /// instead of showing a button that can only fail.
  static bool get isEnabled => AppConstants.stripePublishableKey.isNotEmpty;

  /// Wires up the Stripe SDK. Safe to call when unconfigured (it no-ops), and
  /// safe to call before the first payment — but it must have completed before
  /// any PaymentSheet is presented, so main() awaits it.
  static Future<void> initialize() async {
    if (!isEnabled) return;
    Stripe.publishableKey = AppConstants.stripePublishableKey;
    await Stripe.instance.applySettings();
  }

  /// This team's fee row for [matchId], or null if no charge was ever started.
  Future<MatchPaymentModel?> fetchMyPayment({
    required String matchId,
    required String teamId,
  }) async {
    final data = await SupabaseService.client
        .from(_table)
        .select()
        .eq('match_id', matchId)
        .eq('team_id', teamId)
        .maybeSingle();
    if (data == null) return null;
    return MatchPaymentModel.fromJson(data);
  }

  /// Both teams' fee rows for [matchId], keyed by team id. RLS limits this to
  /// the caller's own team, so a captain sees their own status and simply gets
  /// no row for the opponent — the opposing team's payment state is not ours
  /// to show.
  Future<Map<String, MatchPaymentModel>> fetchForMatch(String matchId) async {
    final data = await SupabaseService.client
        .from(_table)
        .select()
        .eq('match_id', matchId);

    final map = <String, MatchPaymentModel>{};
    for (final e in data as List) {
      final payment = MatchPaymentModel.fromJson(e as Map<String, dynamic>);
      map[payment.teamId] = payment;
    }
    return map;
  }

  /// Runs the full pay flow for the calling captain: asks the Edge Function for
  /// a PaymentIntent, presents Stripe's PaymentSheet, and reports what happened.
  ///
  /// A cancellation is returned as [PaymentOutcome.cancelled] rather than thrown
  /// — dismissing the sheet is a normal thing to do, not an error worth a red
  /// toast.
  Future<PaymentResult> payMatchFee(String matchId) async {
    if (!isEnabled) {
      return const PaymentResult(
        PaymentOutcome.failed,
        'Payments are not configured in this build.',
      );
    }
    if (_uid == null) {
      return const PaymentResult(PaymentOutcome.failed, 'You are signed out.');
    }

    final Map<String, dynamic> body;
    try {
      final res = await SupabaseService.client.functions.invoke(
        _createFn,
        body: {'match_id': matchId},
      );
      body = (res.data as Map?)?.cast<String, dynamic>() ?? const {};
    } catch (e) {
      debugPrint('create-match-payment failed: $e');
      return PaymentResult(PaymentOutcome.failed, _createErrorMessage(e));
    }

    if (body['already_paid'] == true) {
      return const PaymentResult(PaymentOutcome.alreadyPaid);
    }

    final clientSecret = body['client_secret'] as String?;
    if (clientSecret == null || clientSecret.isEmpty) {
      return const PaymentResult(
        PaymentOutcome.failed,
        'Could not start the payment. Please try again.',
      );
    }

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: AppConstants.appName,
          // Stripe's sheet follows the device, which is right: it's a system
          // payment surface, not part of our themed UI.
          style: ThemeMode.system,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return const PaymentResult(PaymentOutcome.succeeded);
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        return const PaymentResult(PaymentOutcome.cancelled);
      }
      return PaymentResult(
        PaymentOutcome.failed,
        e.error.localizedMessage ?? e.error.message ?? 'Your card was declined.',
      );
    } catch (e) {
      debugPrint('presentPaymentSheet failed: $e');
      return const PaymentResult(
        PaymentOutcome.failed,
        'Payment could not be completed. Please try again.',
      );
    }
  }

  /// Waits briefly for Stripe's webhook to land, so the captain sees "Paid"
  /// rather than a stale "Pay €2" button immediately after a successful sheet.
  ///
  /// The sheet returning success means Stripe took the money, but our row is
  /// only written when the webhook arrives — normally within a second or two.
  /// Returning null after the timeout is not a failure: the payment stands, the
  /// row just hasn't caught up, and the next refresh will show it.
  Future<MatchPaymentModel?> awaitConfirmation({
    required String matchId,
    required String teamId,
    Duration timeout = const Duration(seconds: 12),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      try {
        final payment = await fetchMyPayment(matchId: matchId, teamId: teamId);
        if (payment != null && payment.isPaid) return payment;
      } catch (e) {
        // Keep polling: a transient fetch failure shouldn't end the wait.
        debugPrint('awaitConfirmation poll failed: $e');
      }
    }
    return null;
  }

  /// Turns the Edge Function's error codes into something a captain can act on.
  String _createErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('not_a_captain_of_this_match')) {
      return 'Only your team captain can pay the match fee.';
    }
    if (text.contains('match_not_payable')) {
      return 'This match is not open for payment.';
    }
    return 'Could not start the payment. Please try again.';
  }
}
