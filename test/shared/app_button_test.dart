import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';

Widget _host(Widget child, {ThemeData? theme, double textScale = 1}) {
  return MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Center(child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('loading keeps the label and blocks taps until ready', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        AppButton(
          label: 'Save task',
          isLoading: true,
          onPressed: () => calls++,
        ),
      ),
    );

    expect(find.text('Save task'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Save task'));
    await tester.pump();
    expect(calls, 0);

    await tester.pumpWidget(
      _host(AppButton(label: 'Save task', onPressed: () => calls++)),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Save task'));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('outlined variant shows its icon and invokes its callback', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        AppButton(
          label: 'Add task',
          variant: AppButtonVariant.outlined,
          icon: Icons.add,
          onPressed: () => calls++,
        ),
        theme: AppTheme.dark,
      ),
    );

    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    await tester.tap(find.text('Add task'));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('full width button tolerates unbounded Row constraints', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [AppButton(label: 'Continue', onPressed: () {})],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.getSize(find.byType(AppButton)).width, greaterThan(0));
  });

  testWidgets('full width button fits 320 dp at increased text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 320,
          child: AppButton(
            label: 'Save task and continue to focus session',
            icon: Icons.arrow_forward,
            onPressed: () {},
          ),
        ),
        textScale: 1.3,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AppButton)).width, 320);
    expect(
      find.text('Save task and continue to focus session'),
      findsOneWidget,
    );
  });
}
