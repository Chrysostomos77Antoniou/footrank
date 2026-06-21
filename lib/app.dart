import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/routing/app_router.dart';

class FootRankApp extends StatefulWidget {
  const FootRankApp({super.key});

  @override
  State<FootRankApp> createState() => _FootRankAppState();
}

class _FootRankAppState extends State<FootRankApp> {
  late final _router = buildRouter();

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
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
