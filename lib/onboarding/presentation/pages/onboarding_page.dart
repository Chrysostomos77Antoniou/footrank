import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
import 'package:footrank/routing/app_router.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    (
      icon: Icons.sports_soccer,
      title: 'Welcome to FootRank',
      body: 'Turn your casual 5-a-side games into a real competitive ladder.',
    ),
    (
      icon: Icons.groups,
      title: 'Build your team',
      body: 'Create a squad, invite players with a code, and find opponents '
          'in your city.',
    ),
    (
      icon: Icons.emoji_events,
      title: 'Climb the rankings',
      body: 'Play matches, log fair results, and watch your Pitch Power rise '
          'on the leaderboard.',
    ),
    (
      icon: Icons.person_search,
      title: 'No team yet?',
      body: 'Register as a Free Agent and get recruited — or start your own '
          'squad and become the captain.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Finishes onboarding, recording the first-session [intent] (if any) so the
  /// app can route the user somewhere purposeful after they sign in.
  Future<void> _finish({String? intent}) async {
    await OnboardingPrefs.markSeen();
    await OnboardingPrefs.setPostSetupIntent(intent);
    if (mounted) context.go(AppRoutes.login);
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: reduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// The real app icon as a rounded square (falls back to a soccer-ball tile
  /// if the asset is not bundled).
  Widget _logo(bool dark) {
    const size = 88.0;
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          'assets/branding/app_icon_512.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: 'FootRank logo',
          errorBuilder: (context, error, stack) => Container(
            width: size,
            height: size,
            color: dark ? AppColors.heroDarkB : AppColors.limeDeeper,
            child: const Icon(
              Icons.sports_soccer,
              size: size * 0.55,
              color: AppColors.lime,
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroArt(bool dark, double k) {
    final s = _slides[_page];
    final icon = Icon(s.icon, size: 72, color: AppColors.lime);
    // The icon keeps the same spot on every slide; only the first also shows
    // the logo above it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_page == 0)
          _logo(dark)
        else
          const SizedBox(height: 88),
        SizedBox(height: 28 * k),
        icon,
      ],
    );
  }

  Widget _secondaryButton(String label, VoidCallback onTap, bool dark) {
    final color = dark ? AppColors.darkOnSurface : AppColors.limeDeep;
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: AppSemantic.buttonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSemantic.buttonRadius),
          border: Border.all(
            color: dark ? Colors.white.withValues(alpha: 0.24) : color,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;
    final safeBottom = media.padding.bottom;
    final reduce = reduceMotion(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final heroH = (constraints.maxHeight * 0.52).clamp(300.0, 440.0);
          final k = heroH / 440; // scales the pitch markings with the hero
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AuthPitchHero(
                  height: heroH,
                  circleCy: 250 * k,
                  circleR: 130 * k,
                  dotR: 5,
                  boxTop: 110 * k,
                  boxW: 170,
                  boxH: 280 * k,
                  boxVisible: 90,
                  glowAlpha: 0.22,
                  glowRy: 0.8,
                  child: Padding(
                    padding: EdgeInsets.only(top: safeTop + 48 * k),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: reduce ? Duration.zero : AppMotion.quick,
                        child: KeyedSubtree(
                          key: ValueKey(_page),
                          child: _heroArt(dark, k),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: safeTop + 4,
                right: AppSpacing.sm,
                child: TextButton(
                  onPressed: () => _finish(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    foregroundColor: dark
                        ? AppColors.darkSecondary
                        : Colors.white.withValues(alpha: 0.92),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSemantic.controlRadius,
                      ),
                    ),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: heroH - 28,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    36,
                    AppSpacing.xl,
                    28 + safeBottom,
                  ),
                  decoration: BoxDecoration(
                    color: dark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border(
                      top: BorderSide(color: AppColors.border(context)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: dark
                            ? Colors.black.withValues(alpha: 0.3)
                            : AppColors.ink.withValues(alpha: 0.10),
                        blurRadius: dark ? 32 : 20,
                        offset: Offset(0, dark ? -12 : -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemCount: _slides.length,
                          itemBuilder: (context, i) {
                            final s = _slides[i];
                            return Column(
                              children: [
                                FadeSlideIn(
                                  delay: const Duration(milliseconds: 80),
                                  child: Text(
                                    s.title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: AppFonts.display,
                                      color: onSurface,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.26,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                FadeSlideIn(
                                  delay: const Duration(milliseconds: 140),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 310),
                                    child: Text(
                                      s.body,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.muted(context),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Semantics(
                        label: 'Slide ${_page + 1} of ${_slides.length}',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_slides.length, (i) {
                            final active = i == _page;
                            return AnimatedContainer(
                              duration: reduce ? Duration.zero : AppMotion.quick,
                              margin: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xxs - 1,
                              ),
                              width: active ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: active
                                    ? (dark
                                          ? AppColors.lime
                                          : AppColors.limeDeep)
                                    : (dark
                                          ? Colors.white.withValues(alpha: 0.25)
                                          : AppColors.ink.withValues(
                                              alpha: 0.2,
                                            )),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (last) ...[
                        AuthPrimaryButton(
                          loading: false,
                          label: 'Create Your Team →',
                          onPressed: () =>
                              _finish(intent: OnboardingIntent.createTeam),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _secondaryButton(
                          'Register as a Free Agent',
                          () => _finish(intent: OnboardingIntent.freeAgent),
                          dark,
                        ),
                      ] else
                        AuthPrimaryButton(
                          loading: false,
                          label: 'Next',
                          onPressed: _next,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
