import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/widgets/video_splash_overlay.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/services/notification_router.dart';
import 'package:footrank/services/notification_service.dart';

class FootRankApp extends StatefulWidget {
  const FootRankApp({super.key});

  @override
  State<FootRankApp> createState() => _FootRankAppState();
}

class _FootRankAppState extends State<FootRankApp> {
  /// Cold-start branded video splash; removed from the tree once it finishes.
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    // Cold-start via a tapped push notification: getInitialMessage() is
    // called from main() before the router exists, so the actual navigation
    // happens here once it's safe to do so (after the first frame).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await NotificationService.getInitialMessage();
      if (initial != null) {
        handleNotificationTap(
          type: initial.data['type'] as String?,
          referenceId: initial.data['reference_id'] as String?,
        );
      }
    });
  }

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
          routerConfig: appRouter,
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
                // its content's natural size and expose the app underneath.
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
