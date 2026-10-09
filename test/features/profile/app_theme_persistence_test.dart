import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppDependencies> _dependencies(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return AppDependencies(
    prefs: PrefsService(await SharedPreferences.getInstance()),
    hive: HiveService(),
  );
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearPlatformBrightnessTestValue();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('saved ${mode.name} applies on the first app frame', (
      tester,
    ) async {
      final expected = mode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
      tester.platformDispatcher.platformBrightnessTestValue =
          expected == Brightness.dark ? Brightness.light : Brightness.dark;
      final dependencies = await _dependencies({
        AppConstants.themeModeKey: mode.name,
        AppConstants.focusDurationKey: 45,
      });

      await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));

      // No settling or elapsed time: even Splash's first frame is saved-theme.
      expect(find.byType(SplashScreen), findsOneWidget);
      final context = tester.element(find.byType(SplashScreen));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        mode,
      );
      expect(Theme.of(context).brightness, expected);
      expect(context.read<ThemeCubit>().state.mode, mode);
      expect(context.read<SettingsCubit>().state.defaultFocusMinutes, 45);
      expect(dependencies.initialThemeMode, mode);
      expect(dependencies.initialFocusMinutes, 45);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('stored system follows an OS brightness change on the same app', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final dependencies = await _dependencies({
      AppConstants.themeModeKey: 'system',
      AppConstants.focusDurationKey: 15,
    });
    await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
    expect(
      Theme.of(tester.element(find.byType(SplashScreen))).brightness,
      Brightness.light,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(find.byType(SplashScreen))).brightness,
      Brightness.dark,
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect(dependencies.prefs.getInt(AppConstants.focusDurationKey), 15);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live shared Cubits save and a fresh root restores both values', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final dependencies = await _dependencies({});
    await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
    final context = tester.element(find.byType(SplashScreen));
    final theme = context.read<ThemeCubit>();
    final settings = context.read<SettingsCubit>();

    await theme.setMode(ThemeMode.dark);
    await settings.setFocusMinutes(45);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      Theme.of(tester.element(find.byType(SplashScreen))).brightness,
      Brightness.dark,
    );
    expect(settings.state.defaultFocusMinutes, 45);
    expect(dependencies.prefs.getString(AppConstants.themeModeKey), 'dark');
    expect(dependencies.prefs.getInt(AppConstants.focusDurationKey), 45);

    await tester.pumpWidget(const SizedBox.shrink());
    final restored = AppDependencies(
      prefs: dependencies.prefs,
      hive: dependencies.hive,
    );
    await tester.pumpWidget(FocusDeskApp(dependencies: restored));
    final freshContext = tester.element(find.byType(SplashScreen));
    expect(freshContext.read<ThemeCubit>(), isNot(same(theme)));
    expect(freshContext.read<ThemeCubit>().state.mode, ThemeMode.dark);
    expect(freshContext.read<SettingsCubit>().state.defaultFocusMinutes, 45);
    expect(Theme.of(freshContext).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
