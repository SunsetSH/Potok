import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/presentation/settings_screen.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  Widget app(List<SettingsDestination> destinations) => MaterialApp(
    theme: buildPotokTheme(PotokThemeId.studio),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () =>
              showSettingsScreen(context, destinations: destinations),
          child: const Text('open'),
        ),
      ),
    ),
  );

  final destinations = [
    SettingsDestination(
      id: 'first',
      title: 'Первый раздел',
      subtitle: 'Первое описание',
      icon: Icons.palette_outlined,
      builder: (_) => const Text('Первое содержимое'),
    ),
    SettingsDestination(
      id: 'second',
      title: 'Второй раздел',
      subtitle: 'Второе описание',
      icon: Icons.storage_outlined,
      builder: (_) => const Text('Второе содержимое'),
    ),
  ];

  testWidgets('compact settings use a list and a separate section route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(destinations));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-mobile')), findsOneWidget);
    expect(find.text('Первый раздел'), findsOneWidget);
    expect(find.text('Первое содержимое'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-nav-first')));
    await tester.pumpAndSettle();
    expect(find.text('Первое содержимое'), findsOneWidget);
  });

  testWidgets('wide settings use persistent navigation and replace content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(destinations));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-desktop')), findsOneWidget);
    expect(find.text('Первое содержимое'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-nav-second')));
    await tester.pump();
    expect(find.text('Первое содержимое'), findsNothing);
    expect(find.text('Второе содержимое'), findsOneWidget);
  });
}
