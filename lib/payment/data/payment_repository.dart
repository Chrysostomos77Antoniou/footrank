import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:footrank/core/constants/app_constants.dart';
import 'package:footrank/models/match_payment_model.dart';
import 'package:footrank/services/supabase_service.dart';


/// One match where the signed-in captain still owes their team's fee.
///
/// Carries just enough to render an actionable prompt without opening the
/// match: who is playing, when, and how much.
class PendingFee {
  final String matchId;
  final String teamId;
  final String homeTeamName;
  final String awayTeamName;
  final DateTime scheduledAt;
  final String city;

  /// The existing row, when a charge was already attempted (e.g. declined).
  /// Null when nothing has been started yet.
  final MatchPaymentModel? payment;

  const PendingFee({
    required this.matchId,
    required this.teamId,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.scheduledAt,
    required this.city,
    this.payment,
  });

  String get fixture => '$homeTeamName vs $awayTeamName';
  bool get previouslyFailed => payment?.hasFailed ?? false;
  String get amountLabel =>
      payment?.amountLabel ?? MatchPaymentModel.formatAmount(200, 'eur');
}

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
    // Required by the native SDK whenever the PaymentSheet requests Apple
    // Pay (see payMatchFee's `applePay:` param below) -- separate from just
    // passing applePay per-sheet, and separate from the entitlement in
    // Runner.entitlements. Without this, presenting the sheet throws
    // "`merchantIdentifier` is required, but none was found" before it ever
    // opens, on iOS specifically; harmless to set on Android, where it's
    // simply unused. Must match the merchant ID registered in Apple
    // Developer and in Runner.entitlements exactly.
    Stripe.merchantIdentifier = 'merchant.com.footballcy.footrank';
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


  /// Every confirmed match where the signed-in user captains a team that has
  /// not paid yet, soonest first.
  ///
  /// Drives the Home prompt, so a captain sees the outstanding fee the moment
  /// they open the app rather than having to open each match to find it.
  /// Returns empty (never throws) when payments are disabled or the user
  /// captains nothing -- this feeds a banner, and a banner must not be able to
  /// break the home screen.
  Future<List<PendingFee>> fetchPendingFees() async {
    final uid = _uid;
    if (uid == null || !isEnabled) return const [];

    try {
      final teams = await SupabaseService.client
          .from('teams')
          .select('id')
          .eq('captain_id', uid)
          .isFilter('disbanded_at', null);

      final teamIds = (teams as List)
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toList();
      if (teamIds.isEmpty) return const [];

      // `payment_status <> paid` narrows server-side; which SIDE still owes is
      // resolved below from our own match_payments rows (RLS already limits
      // those to this captain's teams).
      final orFilter = teamIds
          .map((id) => 'home_team_id.eq.$id,away_team_id.eq.$id')
          .join(',');

      final matches = await SupabaseService.client
          .from('matches')
          .select(
              'id, scheduled_at, city, home_team_id, away_team_id, payment_status, '
              'home_team:home_team_id(name), away_team:away_team_id(name)')
          .eq('status', 'confirmed')
          .neq('payment_status', 'paid')
          .or(orFilter)
          .order('scheduled_at');

      final rows = (matches as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return const [];

      final paid = <String>{};
      final existing = <String, MatchPaymentModel>{};
      final payments = await SupabaseService.client
          .from(_table)
          .select()
          .inFilter('match_id', rows.map((m) => m['id'] as String).toList());
      for (final e in payments as List) {
        final p = MatchPaymentModel.fromJson(e as Map<String, dynamic>);
        existing['${p.matchId}:${p.teamId}'] = p;
        if (p.isPaid) paid.add('${p.matchId}:${p.teamId}');
      }

      final result = <PendingFee>[];
      for (final m in rows) {
        final matchId = m['id'] as String;
        final home = m['home_team_id'] as String;
        final away = m['away_team_id'] as String;
        final myTeamId = teamIds.contains(home)
            ? home
            : (teamIds.contains(away) ? away : null);
        if (myTeamId == null) continue;

        final key = '$matchId:$myTeamId';
        if (paid.contains(key)) continue; // this side is settled

        result.add(PendingFee(
          matchId: matchId,
          teamId: myTeamId,
          homeTeamName:
              (m['home_team'] as Map?)?['name'] as String? ?? 'Home',
          awayTeamName:
              (m['away_team'] as Map?)?['name'] as String? ?? 'Away',
          scheduledAt: DateTime.parse(m['scheduled_at'] as String),
          city: m['city'] as String? ?? '',
          payment: existing[key],
        ));
      }
      return result;
    } catch (e) {
      debugPrint('fetchPendingFees failed: $e');
      return const [];
    }
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
          // Offers Apple Pay / Google Pay inside the same sheet when the
          // platform and the device both support it -- Stripe silently
          // omits the option otherwise (e.g. a device with no card added to
          // Wallet), so this is safe to pass unconditionally per-platform.
          // Guarded with kIsWeb/defaultTargetPlatform rather than
          // dart:io's Platform, since this repository is also compiled into
          // the web build, where dart:io is unavailable.
          applePay: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
              ? const PaymentSheetApplePay(merchantCountryCode: 'CY')
              : null,
          googlePay:
              (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                  ? const PaymentSheetGooglePay(
                      merchantCountryCode: 'CY',
                      currencyCode: 'EUR',
                      testEnv: false,
                    )
                  : null,
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
