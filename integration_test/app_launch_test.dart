// Phase 1 smoke test: prove the app boots on an emulator in CI and renders its
// first screen. Pumps FootRankApp directly (skipping native splash + push
// notifications from main()) with only the bootstrap the UI needs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:footrank/app.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
import 'package:footrank/services/supabase_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and renders its first screen', (tester) async {
    await themeController.load();
    await OnboardingPrefs.load();
    try {
      await SupabaseService.initialize();
    } catch (_) {
      // Backend/network init must not fail the smoke test — we only assert the
      // app shell renders.
    }

    await tester.pumpWidget(const FootRankApp());
    // Let the router settle to its first screen (avoid pumpAndSettle, which can
    // hang on continuous animations like the splash/loaders).
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
