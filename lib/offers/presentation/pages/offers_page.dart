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

/// Short tagline shown on the listing card and in the popup.
const nemorinTagline = 'Save it. Forget it. Find it.';

/// What the app is, shown in the popup. Edit the copy here.
const nemorinDescription =
    'Nemorin keeps everything worth remembering in one place. Save it in '
    'seconds, forget about it, and find it again when you need it. It can even '
    'remind you based on where you are.';

/// "Offers" -- a small list of deals from other apps. For now it has one
/// listing, Nemorin; tapping it opens a popup with the promo code and a
/// button that goes to the App Store.
class OffersPage extends StatelessWidget {
  const OffersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = AppColors.brand(context);
    final wellFill =
        isDark ? AppColors.lime.withValues(alpha: 0.14) : AppColors.lightChip;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PageHeader(title: 'Offers'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSemantic.screenPadding,
                      AppSpacing.xxs,
                      AppSemantic.screenPadding,
                      AppSpacing.lg),
                  children: [
                    FadeSlideIn(
                      child: PressableScale(
                        onTap: () => showNemorinOffer(context),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkCard
                                : AppColors.lightCard,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: AppColors.border(context)),
                            boxShadow: isDark
                                ? null
                                : [
                                    BoxShadow(
                                      color: AppColors.ink
                                          .withValues(alpha: 0.05),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  'assets/branding/nemorin_preview.png',
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  // Falls back to the tag icon if the image is
                                  // missing.
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 48,
                                    height: 48,
                                    color: wellFill,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.local_offer_outlined,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Nemorin',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.17,
                                        color: onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      nemorinTagline,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.muted(context),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '1 month free  \u00b7  Tap to see offer',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: AppColors.muted(context),
                              ),
                            ],
                          ),
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
    );
  }
}

/// Back button + 26/800 screen title.
class _PageHeader extends StatelessWidget {
  final String title;
  const _PageHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSemantic.screenPadding, AppSpacing.md, AppSemantic.screenPadding,
          AppSpacing.sm),
      child: Row(
        children: [
          PressableScale(
            onTap: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Back',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
                border: Border.all(color: AppColors.border(context)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.05),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_rounded, size: 22, color: onSurface),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.26,
                color: onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Nemorin popup: the code, big and unmissable, and a CLAIM IT button.
Future<void> showNemorinOffer(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showDialog<void>(
    context: context,
    barrierColor: isDark
        ? Colors.black.withValues(alpha: 0.62)
        : AppColors.ink.withValues(alpha: 0.5),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = AppColors.brand(context);
    final wellFill =
        isDark ? AppColors.lime.withValues(alpha: 0.14) : AppColors.lightChip;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : AppColors.lightBorder,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/branding/nemorin_preview.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 64,
                    height: 64,
                    color: wellFill,
                    alignment: Alignment.center,
                    child:
                        Icon(Icons.local_offer_outlined, size: 32, color: accent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nemorin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              nemorinTagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              nemorinDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.muted(context),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Use Promo Code For One Month:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.22,
                height: 1.25,
                color: onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Tap the code to copy it, so it can be pasted into Nemorin.
            Semantics(
              button: true,
              label: 'Copy promo code $nemorinPromoCode',
              child: Material(
                color: wellFill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
                  side: BorderSide(color: accent, width: 1.5),
                ),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
                  ),
                  onTap: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: nemorinPromoCode),
                    );
                    if (context.mounted) {
                      showSuccess(context, 'Code copied');
                    }
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Column(
                      children: [
                        Text(
                          nemorinPromoCode,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                            height: 1.15,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to copy',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
