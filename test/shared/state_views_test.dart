import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: Scaffold(body: SafeArea(child: child)),
  );
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('EmptyView renders its content without an optional action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const EmptyView(
          icon: Icons.task_alt_rounded,
          title: AppStrings.noTasksTitle,
          message: AppStrings.noTasksMessage,
        ),
      ),
    );
    expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
    expect(find.text(AppStrings.noTasksTitle), findsOneWidget);
    expect(find.text(AppStrings.noTasksMessage), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LoadingView renders progress and its optional message', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const LoadingView(message: 'Saving tasks')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving tasks'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_host(const LoadingView()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving tasks'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} EmptyView action works at 320x568', (
      tester,
    ) async {
      _viewport(tester, const Size(320, 568));
      var calls = 0;
      await tester.pumpWidget(
        _host(
          EmptyView(
            icon: Icons.task_alt_rounded,
            title: AppStrings.noTasksTitle,
            message: AppStrings.noTasksMessage,
            actionLabel: AppStrings.addTask,
            onAction: () => calls++,
          ),
          brightness: brightness,
        ),
      );
      await tester.tap(find.text(AppStrings.addTask));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} ErrorView retry works at 320x568', (
      tester,
    ) async {
      _viewport(tester, const Size(320, 568));
      var retries = 0;
      await tester.pumpWidget(
        _host(
          ErrorView(message: AppStrings.networkError, onRetry: () => retries++),
          brightness: brightness,
        ),
      );
      expect(find.text(AppStrings.errorTitle), findsOneWidget);
      expect(find.text(AppStrings.networkError), findsOneWidget);
      await tester.tap(find.text(AppStrings.retry));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} state views scroll in a short viewport', (
      tester,
    ) async {
      _viewport(tester, const Size(320, 180));
      var retries = 0;
      final longMessage = List.filled(8, AppStrings.networkError).join(' ');
      await tester.pumpWidget(
        _host(
          ErrorView(
            title: 'Please try loading your tasks again',
            message: longMessage,
            onRetry: () => retries++,
          ),
          brightness: brightness,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(AppStrings.retry));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.retry));
      expect(retries, 1);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _host(LoadingView(message: longMessage), brightness: brightness),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
