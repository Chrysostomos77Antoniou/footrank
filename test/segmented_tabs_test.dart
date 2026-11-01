// The two switches the Matches screen is built on: SegmentedTabs (the main
// one: Opponents / Activity / Matches) and FilterPills (the quieter ones
// inside a tab). What is checked: labels and counts, taps, what a screen
// reader hears, that the thumb slides (and jumps under reduced motion), and --
// the reason the segments are built the way they are -- that nothing collides
// or overflows on the narrowest phone with the largest text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/widgets/segmented_tabs.dart';

Widget _host(
  Widget child, {
  double textScale = 1,
  bool reduceMotion = false,
}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: app!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [child]),
        ),
      ),
    );

SegmentedTabs _tabs({
  int index = 0,
  List<SegmentedTabItem>? items,
  ValueChanged<int>? onChanged,
}) =>
    SegmentedTabs(
      index: index,
      items: items ??
          const [
            SegmentedTabItem('Opponents'),
            SegmentedTabItem('Activity', badgeCount: 3),
            SegmentedTabItem('Matches'),
          ],
      onChanged: onChanged ?? (_) {},
    );

void _phone(WidgetTester t, {double width = 390}) {
  t.view.physicalSize = Size(width * 2, 1600);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  group('SegmentedTabs', () {
    testWidgets('shows every label, and a count only where there is one',
        (t) async {
      _phone(t);
      await t.pumpWidget(_host(_tabs()));

      expect(find.text('Opponents'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Matches'), findsOneWidget);
      expect(find.byType(CountBadge), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a count stops at 99+', (t) async {
      _phone(t);
      await t.pumpWidget(_host(_tabs(items: const [
        SegmentedTabItem('Activity', badgeCount: 99),
        SegmentedTabItem('Matches', badgeCount: 100),
      ])));

      expect(find.text('99'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('tapping a segment reports its position', (t) async {
      _phone(t);
      final taps = <int>[];
      await t.pumpWidget(_host(_tabs(onChanged: taps.add)));

      await t.tap(find.text('Matches'));
      await t.tap(find.text('Opponents'));
      await t.tap(find.text('Activity'));

      expect(taps, [2, 0, 1]);
    });

    testWidgets('a screen reader hears each label with its count', (t) async {
      _phone(t);
      final handle = t.ensureSemantics();
      await t.pumpWidget(_host(_tabs(index: 1)));

      expect(find.bySemanticsLabel('Activity, 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Opponents'), findsOneWidget);
      expect(find.bySemanticsLabel('Matches'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the thumb slides to the new segment', (t) async {
      _phone(t);
      final thumb = find.descendant(
        of: find.byType(SegmentedTabs),
        matching: find.byType(FractionallySizedBox),
      );

      await t.pumpWidget(_host(_tabs(index: 0)));
      final start = t.getTopLeft(thumb).dx;

      await t.pumpWidget(_host(_tabs(index: 2)));
      await t.pump(const Duration(milliseconds: 50));
      final during = t.getTopLeft(thumb).dx;
      await t.pumpAndSettle();
      final end = t.getTopLeft(thumb).dx;

      expect(during, greaterThan(start));
      expect(during, lessThan(end));
      expect(end, greaterThan(start));
    });

    testWidgets('under reduced motion the thumb jumps instead', (t) async {
      _phone(t);
      final thumb = find.descendant(
        of: find.byType(SegmentedTabs),
        matching: find.byType(FractionallySizedBox),
      );

      await t.pumpWidget(_host(_tabs(index: 0), reduceMotion: true));
      final start = t.getTopLeft(thumb).dx;
      await t.pumpWidget(_host(_tabs(index: 2), reduceMotion: true));
      await t.pump();

      final end = t.getTopLeft(thumb).dx;
      expect(end, greaterThan(start));
      await t.pumpAndSettle();
      expect(t.getTopLeft(thumb).dx, end, reason: 'it was already there');
    });

    for (final (width, scale) in [(320.0, 2.0), (360.0, 1.3), (320.0, 1.0)]) {
      testWidgets('keeps its labels apart at ${width.toInt()}px wide, text '
          'x$scale', (t) async {
        _phone(t, width: width);
        await t.pumpWidget(_host(
          _tabs(items: const [
            SegmentedTabItem('Opponents'),
            SegmentedTabItem('Activity', badgeCount: 120),
            SegmentedTabItem('Matches', badgeCount: 4),
          ]),
          textScale: scale,
        ));

        expect(t.takeException(), isNull, reason: 'no overflow');

        final bar = t.getRect(find.byType(SegmentedTabs));
        final opponents = t.getRect(find.text('Opponents'));
        final activity = t.getRect(find.text('Activity'));
        final matches = t.getRect(find.text('Matches'));
        for (final label in [opponents, activity, matches]) {
          expect(label.left, greaterThanOrEqualTo(bar.left));
          expect(label.right, lessThanOrEqualTo(bar.right));
        }
        expect(opponents.right, lessThan(activity.left));
        expect(activity.right, lessThan(matches.left));
      });
    }
  });

  group('FilterPills', () {
    FilterPills pills({
      int index = 0,
      ValueChanged<int>? onChanged,
      List<FilterPillItem>? items,
    }) =>
        FilterPills(
          index: index,
          items: items ??
              const [
                FilterPillItem('Requests', badgeCount: 2),
                FilterPillItem('Sent'),
                FilterPillItem('To confirm'),
              ],
          onChanged: onChanged ?? (_) {},
        );

    testWidgets('shows its labels and the count', (t) async {
      _phone(t);
      await t.pumpWidget(_host(pills()));

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('To confirm'), findsOneWidget);
      expect(find.byType(CountBadge), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('tapping a pill reports its position', (t) async {
      _phone(t);
      final taps = <int>[];
      await t.pumpWidget(_host(pills(onChanged: taps.add)));

      // The row scrolls sideways when the pills do not all fit, so bring the
      // last one into view the way a thumb would.
      await t.ensureVisible(find.text('To confirm'));
      await t.tap(find.text('To confirm'));
      await t.ensureVisible(find.text('Sent'));
      await t.tap(find.text('Sent'));

      expect(taps, [2, 1]);
    });

    testWidgets('a pill is a full-size tap target even though it looks slimmer',
        (t) async {
      _phone(t);
      await t.pumpWidget(_host(pills()));

      final target = t.getSize(find
          .ancestor(
            of: find.text('Sent'),
            matching: find.byType(ColoredBox),
          )
          .first);
      expect(target.height, greaterThanOrEqualTo(48));
    });

    testWidgets('a screen reader hears each label with its count', (t) async {
      _phone(t);
      final handle = t.ensureSemantics();
      await t.pumpWidget(_host(pills(index: 0)));

      expect(find.bySemanticsLabel('Requests, 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Sent'), findsOneWidget);
      expect(find.bySemanticsLabel('To confirm'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('scrolls sideways instead of squeezing when they do not fit',
        (t) async {
      _phone(t, width: 320);
      await t.pumpWidget(_host(
        pills(items: const [
          FilterPillItem('Requests', badgeCount: 12),
          FilterPillItem('Sent'),
          FilterPillItem('To confirm', badgeCount: 3),
          FilterPillItem('Declined'),
        ]),
        textScale: 1.6,
      ));

      expect(t.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final scroll = t.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
    });
  });
  group('CountBadge', () {
    testWidgets('is as wide as its number needs, however much room it is '
        'offered', (t) async {
      _phone(t);
      await t.pumpWidget(_host(
        const SizedBox(
          width: 300,
          // A Wrap offers its children the whole row; a badge that fills what
          // it is offered turns into a bar.
          child: Wrap(children: [CountBadge(count: 2)]),
        ),
      ));

      final size = t.getSize(find.byType(CountBadge));
      expect(size.width, lessThan(48));
      expect(size.height, lessThan(48));
      expect(size.width, greaterThanOrEqualTo(24));
    });

    testWidgets('sits on the same line as the word it counts', (t) async {
      _phone(t);
      await t.pumpWidget(_host(
        const SizedBox(
          width: 300,
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [Text('PROPOSALS'), CountBadge(count: 2)],
          ),
        ),
      ));

      final word = t.getRect(find.text('PROPOSALS'));
      final badge = t.getRect(find.byType(CountBadge));
      expect(badge.left, greaterThan(word.right));
      expect((badge.center.dy - word.center.dy).abs(), lessThan(4));
    });

    testWidgets('a number that grows makes it wider, up to 99+', (t) async {
      _phone(t);
      await t.pumpWidget(_host(
        const Row(children: [
          CountBadge(count: 2),
          SizedBox(width: 8),
          CountBadge(count: 100),
        ]),
      ));

      final small = t.getSize(find.byType(CountBadge).at(0));
      final large = t.getSize(find.byType(CountBadge).at(1));
      expect(find.text('99+'), findsOneWidget);
      expect(large.width, greaterThan(small.width));
    });
  });
}
