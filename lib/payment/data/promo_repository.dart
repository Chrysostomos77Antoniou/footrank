import 'package:flutter/foundation.dart';
import 'package:footrank/services/supabase_service.dart';

/// What redeeming a promo code came back as.
enum PromoStatus { ok, alreadyRedeemed, invalid, expired, rateLimited, error }

class PromoResult {
  final PromoStatus status;

  /// When the benefit ends (end of the promo), if the server told us.
  final DateTime? validUntil;

  const PromoResult(this.status, [this.validUntil]);

  /// True when the code is now active on the account, whether just now or
  /// earlier -- both mean "your team has no fee".
  bool get isActive =>
      status == PromoStatus.ok || status == PromoStatus.alreadyRedeemed;
}

/// "15 Nov 2026". Kept as a pure top-level function so it's unit-testable and
/// doesn't depend on the device locale (the promo end date is a fixed day).
String promoDateLabel(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  // The promo ends at midnight Cyprus time, i.e. the *start* of the day after
  // the last free day, so label the instant just before it.
  final last = date.toUtc().add(const Duration(hours: 2)).subtract(
        const Duration(seconds: 1),
      );
  return '${last.day} ${months[last.month - 1]} ${last.year}';
}

/// Message shown for a redeem result. Top-level and pure, like
/// [paymentResultMessage], so a dropped case is caught by a unit test.
String promoResultMessage(PromoResult result) {
  final until = result.validUntil != null
      ? promoDateLabel(result.validUntil!)
      : '15 Nov 2026';
  return switch (result.status) {
    PromoStatus.ok => 'Code applied. No booking fees until $until.',
    PromoStatus.alreadyRedeemed =>
      "You've already used this code. No booking fees until $until.",
    PromoStatus.invalid => "That code isn't valid.",
    PromoStatus.expired => 'This code has expired.',
    PromoStatus.rateLimited => 'Too many attempts. Try again in a minute.',
    PromoStatus.error => 'Could not apply the code. Please try again.',
  };
}

/// Redeems promo codes (e.g. WELCOME, which waives the match fee).
///
/// Everything that matters is decided on the server: whether the code exists,
/// whether it has expired, and whether a team's fee is waived. Nothing here can
/// grant itself a waiver -- see `redeem_promo_code` and `team_fee_waived`.
class PromoRepository {
  /// Local mirror of the server's end date (end of 15 Nov 2026, Cyprus time),
  /// used ONLY to decide whether to show the promo prompt at all. The server
  /// still rejects late redemptions on its own.
  static final DateTime promoDeadline = DateTime.utc(2026, 11, 15, 22);

  /// Whether the promo prompt is still worth showing.
  static bool get isOpen => DateTime.now().toUtc().isBefore(promoDeadline);

  Future<PromoResult> redeem(String code) async {
    try {
      final data = await SupabaseService.client.rpc(
        'redeem_promo_code',
        params: {'p_code': code},
      );
      final map = (data as Map).cast<String, dynamic>();
      final until = map['valid_until'] != null
          ? DateTime.tryParse(map['valid_until'] as String)
          : null;
      final status = switch (map['status'] as String?) {
        'ok' => PromoStatus.ok,
        'already_redeemed' => PromoStatus.alreadyRedeemed,
        'invalid' => PromoStatus.invalid,
        'expired' => PromoStatus.expired,
        'rate_limited' => PromoStatus.rateLimited,
        _ => PromoStatus.error,
      };
      return PromoResult(status, until);
    } catch (e) {
      debugPrint('redeem_promo_code failed: $e');
      return const PromoResult(PromoStatus.error);
    }
  }

  /// When the caller's active promo ends, or null if they have none. Never
  /// throws: it only feeds an informational line.
  Future<DateTime?> fetchMyPromoEnd() async {
    try {
      final data = await SupabaseService.client.rpc('my_active_promo');
      if (data == null) return null;
      final raw = (data as Map)['valid_until'] as String?;
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (e) {
      debugPrint('my_active_promo failed: $e');
      return null;
    }
  }

  /// Whether [teamId]'s match fee is currently waived. Never throws; returns
  /// false on any error so the normal pay flow stays available.
  Future<bool> isTeamFeeWaived(String teamId) async {
    try {
      final data = await SupabaseService.client.rpc(
        'my_team_fee_waived',
        params: {'p_team_id': teamId},
      );
      return data == true;
    } catch (e) {
      debugPrint('my_team_fee_waived failed: $e');
      return false;
    }
  }
}
