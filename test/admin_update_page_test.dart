// The admin switch for the "new version" window: what it sends, and that it
// refuses to switch the window on without a real version.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/pages/admin_update_page.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:footrank/core/update/update_prompt.dart';

class FakeUpdateRepo extends AdminRepository {
  UpdatePromptConfig? row;
  Object? loadError;
  final List<(bool, String)> saved = [];

  FakeUpdateRepo({bool enabled = false, String latest = ''})
      : row = UpdatePromptConfig(
          enabled: enabled,
          latestVersion: latest,
          iosUrl: 'https://apps.apple.com/cy/app/x/id1',
          androidUrl: 'https://play.google.com/store/apps/details?id=a.b',
        );

  @override
  Future<UpdatePromptConfig?> fetchUpdatePrompt() async {
    final e = loadError;
    if (e != null) throw e;
    return row;
  }

  @override
  Future<void> setUpdatePrompt({
    required bool enabled,
    required String latestVersion,
  }) async {
    saved.add((enabled, latestVersion));
    row = UpdatePromptConfig(
      enabled: enabled,
      latestVersion: latestVersion,
      iosUrl: row!.iosUrl,
      androidUrl: row!.androidUrl,
    );
  }
}

Future<void> show(WidgetTester t, FakeUpdateRepo repo, {double width = 390}) async {
  t.view.physicalSize = Size(width * 2, 1560);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AdminUpdatePage(repo: repo),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final sw = find.byKey(const Key('update-switch'));
  final version = find.byKey(const Key('update-version'));
  final save = find.byKey(const Key('update-save'));

  bool saveEnabled(WidgetTester t) =>
      t.widget<FilledButton>(save).onPressed != null;

  testWidgets('starts off, with nothing to save', (t) async {
    await show(t, FakeUpdateRepo());
    expect(t.widget<SwitchListTile>(sw).value, isFalse);
    expect(find.textContaining('OFF'), findsOneWidget);
    expect(saveEnabled(t), isFalse);
  });

  testWidgets('shows the saved state and where each store button goes',
      (t) async {
    await show(t, FakeUpdateRepo(enabled: true, latest: '1.1.8'));
    expect(t.widget<SwitchListTile>(sw).value, isTrue);
    expect(t.widget<TextField>(version).controller!.text, '1.1.8');
    expect(find.textContaining('apps.apple.com'), findsOneWidget);
    expect(find.textContaining('play.google.com'), findsOneWidget);
    expect(find.textContaining('never the other way round'), findsOneWidget);
  });

  testWidgets('will not switch on without a version, and sends nothing',
      (t) async {
    final repo = FakeUpdateRepo();
    await show(t, repo);
    await t.tap(sw);
    await t.pump();
    await t.tap(save);
    await t.pump();
    expect(find.text('Enter the newest version first'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('will not accept a version that is not a version', (t) async {
    final repo = FakeUpdateRepo();
    await show(t, repo);
    await t.tap(sw);
    await t.enterText(version, '1.x');
    await t.pump();
    await t.tap(save);
    await t.pump();
    expect(find.text('Use a version like 1.1.8'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('switching on with a version saves both', (t) async {
    final repo = FakeUpdateRepo();
    await show(t, repo);
    await t.tap(sw);
    await t.enterText(version, ' 1.1.8 ');
    await t.pump();
    expect(saveEnabled(t), isTrue);
    await t.tap(save);
    await settle(t);
    expect(repo.saved, [(true, '1.1.8')]);
    expect(find.text('The update window is ON'), findsOneWidget);
    expect(saveEnabled(t), isFalse, reason: 'nothing new to save');
  });

  testWidgets('switching off keeps the version and saves off', (t) async {
    final repo = FakeUpdateRepo(enabled: true, latest: '1.1.8');
    await show(t, repo);
    await t.tap(sw);
    await t.pump();
    await t.tap(save);
    await settle(t);
    expect(repo.saved, [(false, '1.1.8')]);
    expect(find.text('The update window is OFF'), findsOneWidget);
  });

  testWidgets('a server that cannot be reached says so and can retry',
      (t) async {
    final repo = FakeUpdateRepo()..loadError = Exception('offline');
    await show(t, repo);
    expect(find.text('Try again'), findsOneWidget);
    repo.loadError = null;
    await t.tap(find.text('Try again'));
    await settle(t);
    expect(sw, findsOneWidget);
  });

  testWidgets('fits the narrowest phone', (t) async {
    await show(t, FakeUpdateRepo(enabled: true, latest: '1.1.8'), width: 320);
    expect(t.takeException(), isNull);
  });
}
