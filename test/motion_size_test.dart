// MotionSize eases a panel open or shut -- except for people who asked for
// reduced motion, where it must simply change size. (AnimatedSize with a zero
// duration is not that: it asserts in debug builds the first time its size
// changes. The Pitch Power panel, the request cards and the filter bar all hit
// it before they were moved to MotionSize.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/utils/motion.dart';

Widget _host({required double height, bool reduceMotion = false}) =>
    MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(
        body: Column(
          children: [
            MotionSize(
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );

double _heightOfPanel(WidgetTester t) =>
    t.getSize(find.byType(MotionSize)).height;

void main() {
  testWidgets('eases from one size to the other', (t) async {
    await t.pumpWidget(_host(height: 0));
    expect(_heightOfPanel(t), 0);

    await t.pumpWidget(_host(height: 120));
    await t.pump(const Duration(milliseconds: 50));
    expect(_heightOfPanel(t), allOf(greaterThan(0), lessThan(120)),
        reason: 'a quarter of the way through it is between the two');

    await t.pumpAndSettle();
    expect(_heightOfPanel(t), 120);
    expect(t.takeException(), isNull);
  });

  testWidgets('under reduced motion it changes size at once, with no error',
      (t) async {
    await t.pumpWidget(_host(height: 0, reduceMotion: true));
    await t.pumpWidget(_host(height: 120, reduceMotion: true));
    await t.pump();

    expect(_heightOfPanel(t), 120);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(t.takeException(), isNull);

    await t.pumpWidget(_host(height: 0, reduceMotion: true));
    await t.pump();
    expect(_heightOfPanel(t), 0);
    expect(t.takeException(), isNull);
  });
}
