import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';
import 'package:focusdesk/shared/widgets/motion.dart';

Widget _host(Widget child, {bool reduced = false, bool active = true}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: active,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  testWidgets('outgoing state actions cannot receive taps or semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var oldCalls = 0;
    var newCalls = 0;
    Widget panel(String id) => StateMotion(
      stateKey: id,
      child: SizedBox(
        width: 300,
        height: 160,
        child: Align(
          alignment: id == 'old' ? Alignment.topLeft : Alignment.bottomRight,
          child: FilledButton(
            onPressed: () => id == 'old' ? oldCalls++ : newCalls++,
            child: Text('$id action'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(_host(panel('old')));
    await tester.pumpWidget(_host(panel('new')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('old action'), findsOneWidget);
    expect(find.bySemanticsLabel('old action'), findsNothing);
    expect(find.bySemanticsLabel('new action'), findsOneWidget);
    await tester.tap(find.text('old action'), warnIfMissed: false);
    expect(oldCalls, 0);
    await tester.tap(find.text('new action'));
    expect(newCalls, 1);
    await tester.pumpAndSettle();
    expect(find.text('old action'), findsNothing);
    semantics.dispose();
  });

  for (final reduced in [true, false]) {
    testWidgets(
      '${reduced ? 'reduced motion' : 'inactive tab'} switches immediately',
      (tester) async {
        Widget panel(String id) => _host(
          StateMotion(stateKey: id, child: Text(id)),
          reduced: reduced,
          active: reduced,
        );
        await tester.pumpWidget(panel('loading'));
        await tester.pumpWidget(panel('content'));
        expect(find.text('loading'), findsNothing);
        expect(find.text('content'), findsOneWidget);
        expect(find.byType(AnimatedSwitcher), findsNothing);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  }

  testWidgets('entry is bounded and hidden tabs finish without a ticker', (
    tester,
  ) async {
    Widget entry({bool active = true, bool reduced = false}) => _host(
      const MotionEntry(child: Text('Task entry')),
      active: active,
      reduced: reduced,
    );
    await tester.pumpWidget(entry());
    final fade = find.descendant(
      of: find.byType(MotionEntry),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FadeTransition>(fade).opacity.value, greaterThan(0));
    await tester.pumpWidget(entry(active: false));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(entry(reduced: true));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
  });

  testWidgets('compact empty illustration keeps the action usable at 320', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: EmptyView(
              compact: true,
              icon: Icons.checklist_rounded,
              title: 'Ready for your next task',
              message: 'Add a task to begin.',
              actionLabel: 'Add task',
              onAction: () => calls++,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
    expect(find.text('Add task').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Add task'));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
