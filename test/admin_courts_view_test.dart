import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/presentation/pages/admin_courts_page.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

AdminCourtModel _court(
  String id,
  String name,
  String city, {
  bool active = true,
  String? hours,
  String? phone,
  String? address,
}) => AdminCourtModel(
  id: id,
  name: name,
  city: city,
  active: active,
  hours: hours,
  phone: phone,
  address: address,
);

final _courts = [
  _court(
    '1',
    'Keravnos 5s',
    'Nicosia',
    hours: '09:00 - 23:00',
    phone: '99 123456',
    address: 'Strovolos',
  ),
  _court('2', 'Kick On Fives', 'Nicosia', active: false),
  _court('3', 'Wembley', 'Limassol', hours: '10:00 - 00:00'),
  _court('4', 'Park of Colors', 'Limassol'),
  _court('5', 'GC School', 'Larnaca', active: false),
];

Widget _host(List<AdminCourtModel> courts) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: AdminCourtsView(
        courts: courts,
        onEdit: (_) {},
        onToggleActive: (_) {},
      ),
    ),
  ),
);

Finder _menuItem(String label) =>
    find.descendant(of: find.byType(AdminMenuItem), matching: find.text(label));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();
  }

  testWidgets('shows every court and the total', (tester) async {
    await pumpView(tester);
    for (final c in _courts) {
      expect(find.text(c.name), findsOneWidget);
    }
    expect(find.text('5 courts'), findsOneWidget);
  });

  testWidgets('city filter narrows the table and can be cleared', (
    tester,
  ) async {
    await pumpView(tester);

    await tester.tap(find.text('All cities'));
    await tester.pumpAndSettle();
    // Every city in the data is offered, with its count.
    expect(_menuItem('Larnaca'), findsOneWidget);
    expect(_menuItem('Limassol'), findsOneWidget);
    expect(_menuItem('Nicosia'), findsOneWidget);

    await tester.tap(_menuItem('Limassol'));
    await tester.pumpAndSettle();

    expect(find.text('Wembley'), findsOneWidget);
    expect(find.text('Park of Colors'), findsOneWidget);
    expect(find.text('Keravnos 5s'), findsNothing);
    expect(find.text('GC School'), findsNothing);
    expect(find.text('Showing 2 of 5 courts'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('5 courts'), findsOneWidget);
    expect(find.text('Keravnos 5s'), findsOneWidget);
  });

  testWidgets('status and city filters combine', (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('Inactive'));
    await tester.pumpAndSettle();
    expect(find.text('Kick On Fives'), findsOneWidget);
    expect(find.text('GC School'), findsOneWidget);
    expect(find.text('Wembley'), findsNothing);

    await tester.tap(find.text('All cities'));
    await tester.pumpAndSettle();
    await tester.tap(_menuItem('Larnaca'));
    await tester.pumpAndSettle();
    expect(find.text('GC School'), findsOneWidget);
    expect(find.text('Kick On Fives'), findsNothing);

    // Active + Larnaca has no courts -> empty state with a way out.
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('No courts match these filters.'), findsOneWidget);
  });

  testWidgets('columns menu shows and hides columns, and remembers them', (
    tester,
  ) async {
    await pumpView(tester);
    expect(find.text('PHONE'), findsNothing);
    expect(find.text('99 123456'), findsNothing);

    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(_menuItem('Phone'));
    await tester.pumpAndSettle();
    expect(find.text('PHONE'), findsOneWidget);
    expect(find.text('99 123456'), findsOneWidget);

    await tester.tap(_menuItem('Hours'));
    await tester.pumpAndSettle();
    expect(find.text('HOURS'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('admin_courts_columns')!;
    expect(saved, containsAll(['city', 'phone', 'active']));
    expect(saved, isNot(contains('hours')));
  });

  testWidgets('restores saved columns on open', (tester) async {
    SharedPreferences.setMockInitialValues({
      'admin_courts_columns': ['address', 'active'],
    });
    await pumpView(tester);
    expect(find.text('ADDRESS'), findsOneWidget);
    expect(find.text('CITY'), findsNothing);
    expect(find.text('Strovolos'), findsOneWidget);
  });
}
