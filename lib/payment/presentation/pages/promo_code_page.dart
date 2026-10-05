import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
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
      appBar: AppBar(
        toolbarHeight: 68,
        leadingWidth: 64,
        titleSpacing: 0,
        leading: Navigator.of(context).canPop() ? const _BackChip() : null,
        title: Text(
          'Promo code',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.26,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeSlideIn(
                        child: Text(
                          'Have a promo code?',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.22,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 40),
                        child: Text(
                          'Enter it to waive the match fee for you and your team. '
                          'If one player on a team redeems it, the whole team gets '
                          'it.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.muted(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Promo code',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _controller,
                              enabled: !_loading,
                              autocorrect: false,
                              enableSuggestions: false,
                              textCapitalization:
                                  TextCapitalization.characters,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _apply(),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: theme.colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                constraints: const BoxConstraints(
                                    minHeight: 52, maxHeight: 52),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                prefixIcon: Icon(
                                  Icons.confirmation_number_outlined,
                                  size: 20,
                                  color: AppColors.onChip(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 120),
                      child: AppButton(
                        label: 'Apply',
                        icon: Icons.check_rounded,
                        loading: _loading,
                        onPressed: _apply,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 160),
                      child: AppButton(
                        label: 'Skip',
                        variant: AppButtonVariant.secondary,
                        fullWidth: true,
                        onPressed: _loading ? null : () => context.pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: AppSemantic.screenPadding),
      child: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            child: Material(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppSemantic.controlRadius),
                side: BorderSide(color: AppColors.border(context)),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSemantic.controlRadius),
                ),
                onTap: () => Navigator.of(context).maybePop(),
                child: Icon(Icons.chevron_left_rounded,
                    size: 26, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
