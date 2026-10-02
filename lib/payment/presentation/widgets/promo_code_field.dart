import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/payment/data/promo_repository.dart';

/// "Add your promo code" -- the inline entry field at the top of Home.
///
/// Shown only while the promo is open ([PromoRepository.isOpen]). Once the
/// account has an active code it collapses to a one-line "No booking fees
/// until ..." note, so the same prompt never nags someone who already has it.
/// Renders nothing after the promo has ended or while the state is loading.
///
/// Redeeming is entirely server-side (see [PromoRepository.redeem]); this
/// widget only collects the text and reports the result.
class PromoCodeField extends StatefulWidget {
  const PromoCodeField({super.key});

  @override
  State<PromoCodeField> createState() => _PromoCodeFieldState();
}

class _PromoCodeFieldState extends State<PromoCodeField> {
  final _repo = PromoRepository();
  final _controller = TextEditingController();

  bool _loaded = false;
  bool _submitting = false;

  /// When the account's active promo ends, or null if it has none.
  DateTime? _activeUntil;

  @override
  void initState() {
    super.initState();
    _load();
    appRefresh.addListener(_load);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_load);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!PromoRepository.isOpen) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final until = await _repo.fetchMyPromoEnd();
    if (!mounted) return;
    setState(() {
      _activeUntil = until;
      _loaded = true;
    });
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      showError(context, 'Enter a promo code first.');
      return;
    }
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final result = await _repo.redeem(code);
      if (!mounted) return;
      final message = promoResultMessage(result);
      if (result.isActive) {
        showSuccess(context, message);
        _controller.clear();
        setState(() => _activeUntil = result.validUntil ?? _activeUntil);
        // The fee banner and match screens render fee state too.
        triggerAppRefresh();
      } else {
        showError(context, message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !PromoRepository.isOpen) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final brand = AppColors.brand(context);

    final Widget content;
    if (_activeUntil != null) {
      content = GlassCard(
        tint: brand,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: brand, size: AppIconSize.md),
            const SizedBox(width: AppSemantic.iconGap),
            Expanded(
              child: Text(
                'Promo active · No booking fees until '
                '${promoDateLabel(_activeUntil!)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = TextField(
        controller: _controller,
        enabled: !_submitting,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _apply(),
        decoration: InputDecoration(
          labelText: 'Add your promo code',
          prefixIcon: const Icon(Icons.confirmation_number_outlined),
          suffixIcon: _submitting
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _apply,
                  child: const Text('Apply'),
                ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: FadeSlideIn(child: content),
    );
  }
}
