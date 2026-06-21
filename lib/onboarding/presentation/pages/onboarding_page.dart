import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
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
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingPrefs.markSeen();
    if (mounted) context.go(AppRoutes.login);
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
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
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (i == 0) const BrandLogo(size: 88),
                        if (i == 0) const SizedBox(height: 28),
                        Icon(s.icon,
                            size: 72, color: AppColors.iconAccent(context)),
                        const SizedBox(height: 28),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        Text(s.body,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge),
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
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.brand(context)
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
