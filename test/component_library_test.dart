import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/widgets.dart';
import 'package:footrank/models/match_status.dart';

/// Regression coverage for the shared component layer.
///
/// This layer had ZERO tests while 50 GlassCards and 104 FadeSlideIns depended
/// on it. These tests pin the behaviours that were actually wrong before the
/// consolidation — not incidental styling, which would just churn.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.dark}) {
    return MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('StatusChip', () {
    testWidgets('renders the same colour for a state in both brightnesses '
        'relative to its own scheme', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(host(
          const StatusChip(status: MatchStatus.completed),
          brightness: brightness,
        ));
        final text = tester.widget<Text>(find.text('Completed'));
        expect(text.style?.color, AppColors.success,
            reason: 'completed must be the semantic success colour, not a '
                'ColorScheme.fromSeed by-product');
      }
    });

    testWidgets('disputed outranks the lifecycle state', (tester) async {
      // The bug: match_detail_page had no disputed branch, so a disputed
      // match displayed a calm "Completed" on the screen a captain visits to
      // raise the dispute.
      await tester.pumpWidget(host(
        const StatusChip(status: MatchStatus.completed, disputed: true),
      ));
      expect(find.text('Disputed'), findsOneWidget);
      expect(find.text('Completed'), findsNothing);

      final text = tester.widget<Text>(find.text('Disputed'));
      expect(text.style?.color, AppColors.gold);
    });

    testWidgets('confirmed and searching do not render identically',
        (tester) async {
      await tester.pumpWidget(host(
        const StatusChip(status: MatchStatus.confirmed),
      ));
      final confirmed =
          tester.widget<Text>(find.text('Confirmed')).style?.color;

      await tester.pumpWidget(host(
        const StatusChip(status: MatchStatus.searching),
      ));
      final searching =
          tester.widget<Text>(find.text('Searching')).style?.color;

      expect(confirmed, isNot(equals(searching)),
          reason: 'a confirmed fixture and an open request are different '
              'things and must not look the same');
    });

    testWidgets('fromString maps raw DB values', (tester) async {
      await tester.pumpWidget(host(StatusChip.fromString('completed')));
      expect(find.text('Completed'), findsOneWidget,
          reason: 'label should be title-cased from the enum, not the raw '
              'lowercase DB string');
    });

    testWidgets('exposes an accessible label', (tester) async {
      await tester.pumpWidget(host(
        const StatusChip(status: MatchStatus.confirmed),
      ));
      expect(
        tester.getSemantics(find.byType(StatusChip)).label,
        'Match status: Confirmed',
      );
    });
  });

  group('StatTile', () {
    testWidgets('uses tabular figures so digits do not jitter', (tester) async {
      await tester.pumpWidget(host(
        const SizedBox(width: 200, child: StatTile(label: 'Matches', value: '12')),
      ));
      final text = tester.widget<Text>(find.text('12'));
      expect(
        text.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: 'without tabular figures an animated count visibly jitters '
            'and stacked tiles fail to align',
      );
    });

    testWidgets('announces label and value together', (tester) async {
      await tester.pumpWidget(host(
        const SizedBox(
          width: 200,
          child: StatTile(label: 'Reliability', value: '87', suffix: '%'),
        ),
      ));
      expect(
        tester.getSemantics(find.byType(StatTile)).label,
        'Reliability: 87%',
      );
    });

    testWidgets('requires either a value or an animateTo target', (tester) async {
      expect(
        () => StatTile(label: 'x'),
        throwsAssertionError,
      );
    });
  });

  group('AppButton', () {
    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(host(
        const AppButton(label: 'Save', onPressed: null),
      ));
      final semantics = tester.getSemantics(find.byType(AppButton));
      expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
    });

    testWidgets('loading blocks taps and keeps the button mounted',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        AppButton(label: 'Save', loading: true, onPressed: () => taps++),
      ));
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0, reason: 'a loading button must not fire again');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('fires once when enabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        AppButton(label: 'Save', onPressed: () => taps++),
      ));
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('every variant builds and stays tappable', (tester) async {
      for (final variant in AppButtonVariant.values) {
        var taps = 0;
        await tester.pumpWidget(host(
          AppButton(
            label: variant.name,
            variant: variant,
            onPressed: () => taps++,
          ),
        ));
        await tester.tap(find.byType(AppButton));
        await tester.pumpAndSettle();
        expect(taps, 1, reason: '${variant.name} should be tappable');
      }
    });
  });

  group('design tokens', () {
    test('tap target floor meets the accessibility minimum', () {
      // Flutter's own accessibility checklist specifies 48x48; the app
      // previously shipped 44.
      expect(AppSemantic.minTapTarget, greaterThanOrEqualTo(48));
    });

    test('semantic radii resolve to the reference scale', () {
      expect(AppSemantic.cardRadius, AppRadius.lg);
      expect(AppSemantic.controlRadius, AppRadius.md);
      expect(AppSemantic.statusPillRadius, AppRadius.sm);
    });

    test('both themes build without throwing', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
    });
  });
}
