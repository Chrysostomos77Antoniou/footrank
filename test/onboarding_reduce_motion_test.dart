import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/onboarding/presentation/pages/onboarding_page.dart';

/// Regression: with animations disabled (Android "Remove animations" /
/// Reduce Motion) tapping Next used to crash with a LateInitializationError
/// inside Flutter's DrivenScrollActivity because nextPage() was given a zero
/// duration.
void main() {
  for (final disableAnimations in [true, false]) {
    testWidgets('Next advances the slide (disableAnimations=$disableAnimations)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: const OnboardingPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Slide 1 of 4'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Slide 2 of 4'), findsOneWidget);
    });
  }
}
