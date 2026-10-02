import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/payment/data/promo_repository.dart';

/// "Have a promo code?" -- shown once after the Pwr quiz (new accounts) and
/// reachable any time from Profile, so someone who skipped it can still enter
/// the code later.
///
/// Redeeming is entirely server-side; this page only collects the text and
/// reports the result.
class PromoCodePage extends StatefulWidget {
  const PromoCodePage({super.key});

  @override
  State<PromoCodePage> createState() => _PromoCodePageState();
}

class _PromoCodePageState extends State<PromoCodePage> {
  final _repo = PromoRepository();
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      showError(context, 'Enter a promo code first.');
      return;
    }
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final result = await _repo.redeem(code);
      if (!mounted) return;
      final message = promoResultMessage(result);
      if (result.isActive) {
        showSuccess(context, message);
        // Home's fee banner and the match screens render fee state.
        triggerAppRefresh();
        context.pop();
      } else {
        showError(context, message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Promo code')),
      body: AmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeSlideIn(
                  child: Text(
                    'Have a promo code?',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 40),
                  child: Text(
                    'Enter it to waive the match fee for you and your team. '
                    'If one player on a team redeems it, the whole team gets '
                    'it.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: TextField(
                    controller: _controller,
                    enabled: !_loading,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _apply(),
                    decoration: const InputDecoration(
                      labelText: 'Promo code',
                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: AppButton(
                    label: 'Apply',
                    icon: Icons.check_rounded,
                    loading: _loading,
                    onPressed: _apply,
                  ),
                ),
                const SizedBox(height: 8),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: AppButton(
                    label: 'Skip',
                    variant: AppButtonVariant.secondary,
                    onPressed: _loading ? null : () => context.pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
