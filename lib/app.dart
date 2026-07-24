import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/widgets/video_splash_overlay.dart';
import 'package:footrank/routing/app_router.dart';

class FootRankApp extends StatefulWidget {
  const FootRankApp({super.key});

  @override
  State<FootRankApp> createState() => _FootRankAppState();
}

class _FootRankAppState extends State<FootRankApp> {
  late final _router = buildRouter();

  /// Cold-start branded video splash; removed from the tree once it finishes.
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'FootRank',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeController.mode,
          // Switch palettes instantly instead of cross-fading every colour over
          // ~200ms (which looked slow/laggy on long lists).
          themeAnimationDuration: Duration.zero,
          routerConfig: _router,
          builder: (context, child) {
            // Honour the user's font-size setting, but clamp it so very large
            // scales don't break layouts.
            final mq = MediaQuery.of(context);
            final clamped = mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            );
            return MediaQuery(
              data: mq.copyWith(textScaler: clamped),
              // The video splash sits above the booting app (router, auth
              // redirects, etc. all resolve underneath it), then fades away
              // -- no routing involved, so deep links stay untouched.
              child: Stack(
                // Force both layers to the full screen size -- without this,
                // the overlay (and its fallback background) can collapse to
                // its content's natural size and expose the app underneath
                // at the edges, or entirely, while the video is loading.
                fit: StackFit.expand,
                children: [
                  child ?? const SizedBox.shrink(),
                  if (!_splashDone)
                    VideoSplashOverlay(
                      onFinished: () => setState(() => _splashDone = true),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
