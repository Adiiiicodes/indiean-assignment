import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_dependencies.dart';

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearPlatformBrightnessTestValue();
  });

  for (final coldDark in [true, false]) {
    testWidgets(
      '${coldDark ? 'saved' : 'live'} dark Login uses light system-bar icons on a light OS',
      (tester) async {
        final dispatched = <Map<Object?, Object?>>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
              dispatched.add(Map<Object?, Object?>.from(call.arguments as Map));
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        SharedPreferences.setMockInitialValues({
          if (coldDark) AppConstants.themeModeKey: ThemeMode.dark.name,
        });
        final preferences = await SharedPreferences.getInstance();
        final dependencies = AppDependencies(
          prefs: PrefsService(preferences),
          hive: HiveService(),
        );
        addTearDown(() => dependencies.dio.close(force: true));
        await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
        await tester.pump(const Duration(milliseconds: 1200));
        await tester.pumpAndSettle();
        final login = tester.element(find.byType(LoginScreen));
        if (!coldDark) {
          await login.read<ThemeCubit>().setMode(ThemeMode.dark);
          await tester.pumpAndSettle();
        }
        expect(Theme.of(login).brightness, Brightness.dark);
        final regions = tester
            .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byWidgetPredicate(
                (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
              ),
            );
        expect(regions, hasLength(1));
        final rootStyle = regions.single.value;
        expect(rootStyle.statusBarIconBrightness, Brightness.light);
        expect(rootStyle.systemNavigationBarIconBrightness, Brightness.light);
        expect(rootStyle.systemNavigationBarContrastEnforced, isTrue);
        final layer = tester.layers.first as ContainerLayer;
        final status = layer.find<SystemUiOverlayStyle>(const Offset(180, 12));
        final navigation = layer.find<SystemUiOverlayStyle>(
          const Offset(180, 627),
        );
        expect(status?.statusBarIconBrightness, Brightness.light);
        expect(navigation?.systemNavigationBarIconBrightness, Brightness.light);
        expect(navigation?.systemNavigationBarContrastEnforced, isTrue);
        expect(dispatched, isNotEmpty);
        final nativeStyle = dispatched.last;
        expect(nativeStyle['statusBarIconBrightness'], 'Brightness.light');
        expect(
          nativeStyle['systemNavigationBarIconBrightness'],
          'Brightness.light',
        );
        expect(nativeStyle['systemNavigationBarContrastEnforced'], isTrue);
        expect(
          nativeStyle['systemNavigationBarColor'],
          Theme.of(login).colorScheme.surface.toARGB32(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('app follows system ${brightness.name} theme', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;

      final dependencies = await createTestDependencies();
      await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.brightness, brightness);
      expect(theme.colorScheme.brightness, brightness);
      expect(theme.useMaterial3, isTrue);
      final style = AppTheme.systemOverlay(theme.colorScheme);
      expect(style.systemNavigationBarContrastEnforced, isTrue);
      expect(
        style.systemNavigationBarIconBrightness,
        brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      );
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
