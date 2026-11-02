// The "new version" window: who sees it, where its button goes, and that
// nothing can close it. iPhone must reach the App Store and Android must reach
// Google Play -- never the other way round.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/update/update_prompt.dart';
import 'package:footrank/core/widgets/update_prompt_gate.dart';

const _appStore =
    'https://apps.apple.com/cy/app/footrank-5-a-side-ranking/id6789153684';
const _playWeb =
    'https://play.google.com/store/apps/details?id=com.footballcy.footrank';

UpdatePromptConfig config({
  bool enabled = true,
  String latest = '1.1.8',
  String ios = _appStore,
  String android = _playWeb,
}) =>
    UpdatePromptConfig(
      enabled: enabled,
      latestVersion: latest,
      iosUrl: ios,
      androidUrl: android,
    );

void main() {
  group('Version comparison', () {
    test('an older build is older, a same or newer one is not', () {
      expect(isOlderVersion('1.1.7', '1.1.8'), isTrue);
      expect(isOlderVersion('1.1.7+235', '1.1.8'), isTrue);
      expect(isOlderVersion('1.1.8', '1.1.8'), isFalse);
      expect(isOlderVersion('1.1.8+300', '1.1.8'), isFalse);
      expect(isOlderVersion('1.2.0', '1.1.9'), isFalse);
      expect(isOlderVersion('2.0.0', '1.9.9'), isFalse);
    });

    test('compares numbers, not text, and treats a missing part as zero', () {
      expect(isOlderVersion('1.9.0', '1.10.0'), isTrue);
      expect(isOlderVersion('1.10.0', '1.9.0'), isFalse);
      expect(isOlderVersion('1.1', '1.1.1'), isTrue);
      expect(isOlderVersion('1.1.0', '1.1'), isFalse);
    });

    test('anything that does not parse never locks anybody out', () {
      expect(isOlderVersion('1.1.7', ''), isFalse);
      expect(isOlderVersion('1.1.7', 'soon'), isFalse);
      expect(isOlderVersion('', '1.1.8'), isFalse);
      expect(isOlderVersion('abc', '1.1.8'), isFalse);
      expect(isOlderVersion('1.1.7', '1.1.8.2'), isFalse);
    });

    test('the admin panel accepts only real versions', () {
      for (final ok in ['1.1.8', '1.1', ' 2.0.1 ']) {
        expect(isValidVersion(ok), isTrue, reason: ok);
      }
      for (final bad in ['', '1', '1.x', 'v1.1.8', '1.1.8+9', '1.1.8.1']) {
        expect(isValidVersion(bad), isFalse, reason: bad);
      }
    });
  });

  group('Store links', () {
    test('only iPhone and Android have a store', () {
      expect(storePlatformFor(TargetPlatform.iOS), StorePlatform.ios);
      expect(storePlatformFor(TargetPlatform.android), StorePlatform.android);
      expect(storePlatformFor(TargetPlatform.macOS), isNull);
      expect(storePlatformFor(TargetPlatform.windows), isNull);
      expect(storePlatformFor(TargetPlatform.linux), isNull);
    });

    test('an iPhone gets the App Store page and nothing from Google Play', () {
      final uris = storeUrisFor(config(), StorePlatform.ios);
      expect(uris.map((u) => u.toString()), [_appStore]);
    });

    test('an Android phone opens the Play Store app, then the web page', () {
      final uris = storeUrisFor(config(), StorePlatform.android);
      expect(uris.map((u) => u.toString()), [
        'market://details?id=com.footballcy.footrank',
        _playWeb,
      ]);
      expect(uris.any((u) => u.host.contains('apple.com')), isFalse);
    });

    test('a link typed without https and with extra parameters still works',
        () {
      final typed = config(
        android:
            'play.google.com/store/apps/details?id=com.footballcy.footrank&pli=1',
      );
      final uris = storeUrisFor(typed, StorePlatform.android);
      expect(uris.first.toString(),
          'market://details?id=com.footballcy.footrank');
      expect(uris.last.scheme, 'https');
      expect(uris.last.host, 'play.google.com');
    });

    test('a missing link means there is nothing to open', () {
      expect(storeUrisFor(config(ios: ''), StorePlatform.ios), isEmpty);
      expect(storeUrisFor(config(android: '  '), StorePlatform.android),
          isEmpty);
    });
  });

  group('The window', () {
    final opened = <Uri>[];
    var openResults = <bool>[];

    setUp(() {
      opened.clear();
      openResults = [];
    });

    Future<bool> launcher(Uri uri) async {
      opened.add(uri);
      return openResults.isEmpty ? true : openResults.removeAt(0);
    }

    Future<void> show(
      WidgetTester t, {
      Future<UpdatePromptConfig?> Function()? load,
      String installed = '1.1.7',
      TargetPlatform platform = TargetPlatform.iOS,
      VoidCallback? onUnderneathTap,
    }) async {
      t.view.physicalSize = const Size(780, 1560);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Stack(
            fit: StackFit.expand,
            children: [
              Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: onUnderneathTap ?? () {},
                    child: const Text('Underneath'),
                  ),
                ),
              ),
              UpdatePromptGate(
                configLoader: load ?? () async => config(),
                versionLoader: () async => installed,
                launcher: launcher,
                platform: platform,
              ),
            ],
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    final window = find.byKey(const Key('update-prompt'));

    testWidgets('switched off: nobody sees anything', (t) async {
      await show(t, load: () async => config(enabled: false));
      expect(window, findsNothing);
    });

    testWidgets('switched on and the build is older: the window shows',
        (t) async {
      await show(t);
      expect(window, findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('someone already on the newest version is not asked',
        (t) async {
      await show(t, installed: '1.1.8');
      expect(window, findsNothing);
      await show(t, installed: '1.2.0');
      expect(window, findsNothing);
    });

    testWidgets('no row, a failing server or a blank version: no window',
        (t) async {
      await show(t, load: () async => null);
      expect(window, findsNothing);
      await show(t, load: () async => throw Exception('offline'));
      expect(window, findsNothing);
      await show(t, load: () async => config(latest: ''));
      expect(window, findsNothing);
    });

    testWidgets('web and desktop never get it', (t) async {
      await show(t, platform: TargetPlatform.macOS);
      expect(window, findsNothing);
    });

    testWidgets('an iPhone is sent to the App Store, never to Google Play',
        (t) async {
      await show(t, platform: TargetPlatform.iOS);
      await t.tap(find.text('Update now'));
      await t.pump();
      expect(opened.map((u) => u.toString()), [_appStore]);
    });

    testWidgets('an Android phone is sent to Google Play, never to the App Store',
        (t) async {
      await show(t, platform: TargetPlatform.android);
      await t.tap(find.text('Update now'));
      await t.pump();
      expect(opened.single.toString(),
          'market://details?id=com.footballcy.footrank');
      expect(opened.any((u) => u.host.contains('apple.com')), isFalse);
    });

    testWidgets('if the Play Store app will not open, the web page does',
        (t) async {
      openResults = [false, true];
      await show(t, platform: TargetPlatform.android);
      await t.tap(find.text('Update now'));
      await t.pump();
      expect(opened.map((u) => u.toString()), [
        'market://details?id=com.footballcy.footrank',
        _playWeb,
      ]);
    });

    testWidgets('nothing closes it: not a tap outside, not the app below',
        (t) async {
      var underneath = 0;
      await show(t, onUnderneathTap: () => underneath++);
      await t.tapAt(const Offset(8, 8));
      await t.pump(const Duration(milliseconds: 300));
      expect(window, findsOneWidget);
      await t.tap(find.text('Underneath'), warnIfMissed: false);
      await t.pump();
      expect(underneath, 0, reason: 'the app below must not receive touches');
      expect(window, findsOneWidget);
    });

    testWidgets('it asks again when the app comes back to the front',
        (t) async {
      var on = false;
      await show(t, load: () async => config(enabled: on));
      expect(window, findsNothing);

      on = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(window, findsOneWidget);

      on = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(window, findsNothing);
    });

    testWidgets('a failing check keeps whatever was showing', (t) async {
      var fail = false;
      await show(
        t,
        load: () async => fail ? throw Exception('offline') : config(),
      );
      expect(window, findsOneWidget);
      fail = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(window, findsOneWidget);
    });

    testWidgets('the narrowest phone with the largest text still fits',
        (t) async {
      t.view.physicalSize = const Size(640, 1136);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: c!,
          ),
          home: Stack(
            fit: StackFit.expand,
            children: [
              const Scaffold(),
              UpdatePromptGate(
                configLoader: () async => config(),
                versionLoader: () async => '1.1.7',
                launcher: launcher,
                platform: TargetPlatform.iOS,
              ),
            ],
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(window, findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
