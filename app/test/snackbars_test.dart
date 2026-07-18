import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/presentation/snackbars.dart';

void main() {
  testWidgets('compact snackbar follows text and stays centered', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final snackBar = compactSnackBar(context, 'Заметка сохранена');
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.duration, const Duration(seconds: 4));
    expect(snackBar.width, isNotNull);
    expect(snackBar.width!, lessThan(400));
  });

  testWidgets('action snackbar disappears after four seconds', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                PotokSnackBar(
                  content: const Text('Moved'),
                  action: SnackBarAction(label: 'Undo', onPressed: () {}),
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    expect(find.text('Moved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Moved'), findsNothing);
  });
}
