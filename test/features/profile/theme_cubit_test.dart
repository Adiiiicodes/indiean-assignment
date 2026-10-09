import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPrefs extends Mock implements PrefsService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockPrefs prefs;
  setUp(() {
    prefs = _MockPrefs();
    when(() => prefs.getString(AppConstants.themeModeKey)).thenReturn(null);
  });

  for (final mode in ThemeMode.values) {
    test('loads persisted ${mode.name} before the first state', () async {
      when(() => prefs.getString(AppConstants.themeModeKey))
          .thenReturn(mode.name);
      expect(ThemeCubit.loadMode(prefs), mode);
      final cubit = ThemeCubit(prefs);
      expect(cubit.state, ThemeState(mode: mode));
      await cubit.close();
    });
  }

  for (final stored in <String?>[null, '', 'unsupported', 'DARK']) {
    test('missing or invalid stored value $stored defaults to system', () {
      when(() => prefs.getString(AppConstants.themeModeKey)).thenReturn(stored);
      expect(ThemeCubit.loadMode(prefs), ThemeMode.system);
    });
  }

  test('wrong stored type reports storage failure to bootstrap', () async {
    SharedPreferences.setMockInitialValues({AppConstants.themeModeKey: 42});
    final realPrefs = PrefsService(await SharedPreferences.getInstance());
    expect(
      () => ThemeCubit.loadMode(realPrefs),
      throwsA(isA<StorageException>()),
    );
  });

  test('explicit bootstrap mode skips another preference read', () async {
    final cubit = ThemeCubit(prefs, initialMode: ThemeMode.dark);
    expect(cubit.state, const ThemeState(mode: ThemeMode.dark));
    verifyNever(() => prefs.getString(any()));
    await cubit.close();
  });

  blocTest<ThemeCubit, ThemeState>(
    'persists a selected mode before changing the visible selection',
    build: () {
      when(() => prefs.setString(AppConstants.themeModeKey, 'dark'))
          .thenAnswer((_) async {});
      return ThemeCubit(prefs, initialMode: ThemeMode.light);
    },
    act: (cubit) => cubit.setMode(ThemeMode.dark),
    expect: () => [
      const ThemeState(mode: ThemeMode.light, isSaving: true),
      const ThemeState(mode: ThemeMode.dark),
    ],
    verify: (_) =>
        verify(() => prefs.setString(AppConstants.themeModeKey, 'dark'))
            .called(1),
  );

  blocTest<ThemeCubit, ThemeState>(
    'failed save retains the previous selection with a friendly error',
    build: () {
      when(() => prefs.setString(AppConstants.themeModeKey, 'dark'))
          .thenThrow(const StorageException());
      return ThemeCubit(prefs, initialMode: ThemeMode.light);
    },
    act: (cubit) => cubit.setMode(ThemeMode.dark),
    expect: () => [
      const ThemeState(mode: ThemeMode.light, isSaving: true),
      const ThemeState(
        mode: ThemeMode.light,
        errorMessage: AppStrings.storageError,
      ),
    ],
  );

  test(
    'real preferences survive a newly created cubit for all selections',
    () async {
      SharedPreferences.setMockInitialValues({});
      final realPrefs = PrefsService(await SharedPreferences.getInstance());
      for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
        final cubit = ThemeCubit(realPrefs);
        await cubit.setMode(mode);
        expect(realPrefs.getString(AppConstants.themeModeKey), mode.name);
        await cubit.close();
        final restored = ThemeCubit(realPrefs);
        expect(restored.state.mode, mode);
        await restored.close();
      }
    },
  );

  test(
    'rapid calls serialize writes and retain the last persisted selection',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      final writes = <String>[];
      when(() => prefs.setString(AppConstants.themeModeKey, any()))
          .thenAnswer((invocation) async {
            final value = invocation.positionalArguments[1] as String;
            writes.add(value);
            if (writes.length == 1) {
              started.complete();
              await gate.future;
            }
          });
      final cubit = ThemeCubit(prefs, initialMode: ThemeMode.system);
      final dark = cubit.setMode(ThemeMode.dark);
      final light = cubit.setMode(ThemeMode.light);
      await started.future;
      expect(writes, ['dark']);
      expect(
        cubit.state,
        const ThemeState(mode: ThemeMode.system, isSaving: true),
      );
      gate.complete();
      await Future.wait([dark, light]);
      expect(writes, ['dark', 'light']);
      expect(cubit.state, const ThemeState(mode: ThemeMode.light));
      await cubit.close();
    },
  );

  blocTest<ThemeCubit, ThemeState>(
    'a failed write does not block the next selection or retain its error',
    build: () {
      when(() => prefs.setString(AppConstants.themeModeKey, 'dark'))
          .thenThrow(const StorageException());
      when(() => prefs.setString(AppConstants.themeModeKey, 'light'))
          .thenAnswer((_) async {});
      return ThemeCubit(prefs, initialMode: ThemeMode.system);
    },
    act: (cubit) async {
      await cubit.setMode(ThemeMode.dark);
      await cubit.setMode(ThemeMode.light);
    },
    expect: () => [
      const ThemeState(mode: ThemeMode.system, isSaving: true),
      const ThemeState(
        mode: ThemeMode.system,
        errorMessage: AppStrings.storageError,
      ),
      const ThemeState(mode: ThemeMode.system, isSaving: true),
      const ThemeState(mode: ThemeMode.light),
    ],
  );

  test('close suppresses late state changes and skips queued writes', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final writes = <String>[];
    when(() => prefs.setString(AppConstants.themeModeKey, any()))
        .thenAnswer((invocation) async {
          writes.add(invocation.positionalArguments[1] as String);
          started.complete();
          await gate.future;
        });
    final cubit = ThemeCubit(prefs, initialMode: ThemeMode.system);
    final first = cubit.setMode(ThemeMode.dark);
    final queued = cubit.setMode(ThemeMode.light);
    await started.future;
    final stateAtClose = cubit.state;
    await cubit.close();
    gate.complete();
    await Future.wait([first, queued]);
    await cubit.setMode(ThemeMode.light);
    expect(writes, ['dark']);
    expect(cubit.state, stateAtClose);
  });
}
