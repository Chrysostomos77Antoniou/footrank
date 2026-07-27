import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/presentation/widgets/auth_video_background.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
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
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: AuthVideoBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _finish(),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _slides.length,
                  itemBuilder: (context, i) {
                    final s = _slides[i];
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (i == 0) ...[
                            const FadeSlideIn(child: BrandLogo(size: 88)),
                            const SizedBox(height: AppSpacing.xl),
                          ],
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Icon(s.icon,
                                size: 72, color: AppColors.lime),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 140),
                            child: Text(s.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Sora',
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                )),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 200),
                            child: Text(s.body,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 15,
                                  height: 1.5,
                                )),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: AppMotion.quick,
                    margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs),
                    width: active ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.lime
                          : Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: last
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AuthPrimaryButton(
                            loading: false,
                            label: 'Create Your Team →',
                            onPressed: () =>
                                _finish(intent: OnboardingIntent.createTeam),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () =>
                                  _finish(intent: OnboardingIntent.freeAgent),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.white),
                              child: const Text('Register as a Free Agent'),
                            ),
                          ),
                        ],
                      )
                    : AuthPrimaryButton(
                        loading: false,
                        label: 'Next',
                        onPressed: _next,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
