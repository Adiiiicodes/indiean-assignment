import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/core/theme/app_theme.dart';

import '../helpers/app_dependencies.dart';

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearPlatformBrightnessTestValue();
  });

  for (final brightness in Brightness.values) {
    testWidgets('app follows system ${brightness.name} theme', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;

      final dependencies = await createTestDependencies();
      await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.brightness, brightness);
      expect(theme.colorScheme.brightness, brightness);
      expect(theme.useMaterial3, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${brightness.name} controls work at narrow width and large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var actions = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.light
                : AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Plan a focused work session'),
                        ),
                      ),
                      const TextField(
                        decoration: InputDecoration(labelText: 'Task title'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => actions++,
                        child: const Text('Start focus session'),
                      ),
                      OutlinedButton(
                        onPressed: () => actions++,
                        child: const Text('Save for later'),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(label: Text('High priority')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(FilledButton));
        await tester.tap(find.byType(OutlinedButton));
        expect(actions, 2);
        await tester.enterText(find.byType(TextField), 'Read one chapter');
        await tester.pump();
        expect(find.text('Read one chapter'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
