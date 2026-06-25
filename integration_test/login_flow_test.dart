// Phase 3 first real flow test: drive the login screen against the mock backend
// and verify the app routes through to the authenticated HomePage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:footrank/app.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/home/presentation/pages/home_page.dart';

import 'support/mock_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('email login routes to the home screen', (tester) async {
    await themeController.load();
    await OnboardingPrefs.markSeen(); // skip first-run onboarding
    await SupabaseService.initialize(httpClient: buildMockClient());

    await tester.pumpWidget(const FootRankApp());
    await tester.pump(const Duration(seconds: 1)); // settle to /login

    // Fill the email + password fields and submit.
    final fields = find.byType(TextFormField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.at(0), 'qa@test.dev');
    await tester.enterText(fields.at(1), 'password123');

    await tester.tap(find.text('Login'));
    // Allow auth + the router's hasProfile() check to resolve.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(HomePage), findsOneWidget);
  });
}
