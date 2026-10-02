import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';

/// Where a partner offer sends people.
const nemorinAppStoreUrl =
    'https://apps.apple.com/cy/app/nemorin/id6810692801';

/// The promo code shown in the Nemorin offer.
const nemorinPromoCode = 'FOOTRANK';

/// "Offers" -- a small list of deals from other apps. For now it has one
/// listing, Nemorin; tapping it opens a popup with the promo code and a
/// button that goes to the App Store.
class OffersPage extends StatelessWidget {
  const OffersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.iconAccent(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Offers')),
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              FadeSlideIn(
                child: GlassCard(
                  onTap: () => showNemorinOffer(context),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg - 4),
                        child: Image.asset(
                          'assets/branding/nemorin_preview.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          // Falls back to the tag icon if the image is missing.
                          errorBuilder: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: accent.withValues(alpha: 0.14),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.local_offer_outlined,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nemorin',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tap to see your offer',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.muted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Nemorin popup: the code, big and unmissable, and a CLAIM IT button.
Future<void> showNemorinOffer(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _NemorinOfferDialog(),
  );
}

class _NemorinOfferDialog extends StatelessWidget {
  const _NemorinOfferDialog();

  Future<void> _claim(BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse(nemorinAppStoreUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      showError(context, 'Could not open the App Store');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.iconAccent(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.local_offer_rounded, size: 40, color: accent),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Use Promo Code For One Month:',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Tap the code to copy it, so it can be pasted into Nemorin.
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: nemorinPromoCode),
                );
                if (context.mounted) {
                  showSuccess(context, 'Code copied');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: accent, width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      nemorinPromoCode,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to copy',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'CLAIM IT',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => _claim(context),
            ),
          ],
        ),
      ),
    );
  }
}
