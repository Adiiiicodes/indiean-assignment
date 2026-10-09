import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/settings_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPrefs extends Mock implements PrefsService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockPrefs prefs;
  setUp(() {
    prefs = _MockPrefs();
    when(() => prefs.getInt(AppConstants.focusDurationKey)).thenReturn(null);
  });

  for (final minutes in AppConstants.focusMinutesOptions) {
    test('loads persisted $minutes minutes before the first state', () async {
      when(() => prefs.getInt(AppConstants.focusDurationKey))
          .thenReturn(minutes);
      expect(SettingsCubit.loadMinutes(prefs), minutes);
      final cubit = SettingsCubit(prefs);
      expect(cubit.state, SettingsState(defaultFocusMinutes: minutes));
      await cubit.close();
    });
  }

  for (final stored in <int?>[null, 0, -15, 30, 999]) {
    test(
      'missing or invalid stored minutes $stored default to 25 without a write',
      () {
        when(() => prefs.getInt(AppConstants.focusDurationKey))
            .thenReturn(stored);
        expect(
          SettingsCubit.loadMinutes(prefs),
          AppConstants.defaultFocusMinutes,
        );
        verifyNever(() => prefs.setInt(any(), any()));
      },
    );
  }

  test('wrong stored type reports storage failure to bootstrap', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.focusDurationKey: '45',
    });
    final realPrefs = PrefsService(await SharedPreferences.getInstance());
    expect(
      () => SettingsCubit.loadMinutes(realPrefs),
      throwsA(isA<StorageException>()),
    );
  });

  test('explicit bootstrap minutes skip another read and invalid initial minutes fall back', () async {
    final cubit = SettingsCubit(prefs, initialMinutes: 45);
    expect(cubit.state, const SettingsState(defaultFocusMinutes: 45));
    final invalid = SettingsCubit(prefs, initialMinutes: 99);
    expect(invalid.state, const SettingsState(defaultFocusMinutes: 25));
    verifyNever(() => prefs.getInt(any()));
    await cubit.close();
    await invalid.close();
  });

  blocTest<SettingsCubit, SettingsState>(
    'persists selected minutes before changing the visible selection',
    build: () {
      when(() => prefs.setInt(AppConstants.focusDurationKey, 45))
          .thenAnswer((_) async {});
      return SettingsCubit(prefs, initialMinutes: 15);
    },
    act: (cubit) => cubit.setFocusMinutes(45),
    expect: () => [
      const SettingsState(defaultFocusMinutes: 15, isSaving: true),
      const SettingsState(defaultFocusMinutes: 45),
    ],
    verify: (_) =>
        verify(() => prefs.setInt(AppConstants.focusDurationKey, 45)).called(1),
  );

  blocTest<SettingsCubit, SettingsState>(
    'failed save retains previous minutes with a friendly storage error',
    build: () {
      when(() => prefs.setInt(AppConstants.focusDurationKey, 45))
          .thenThrow(const StorageException());
      return SettingsCubit(prefs, initialMinutes: 15);
    },
    act: (cubit) => cubit.setFocusMinutes(45),
    expect: () => [
      const SettingsState(defaultFocusMinutes: 15, isSaving: true),
      const SettingsState(
        defaultFocusMinutes: 15,
        errorMessage: AppStrings.storageError,
      ),
    ],
  );

  for (final minutes in [-1, 0, 20, 60]) {
    blocTest<SettingsCubit, SettingsState>(
      'unsupported requested duration $minutes never persists',
      build: () => SettingsCubit(prefs, initialMinutes: 45),
      act: (cubit) => cubit.setFocusMinutes(minutes),
      expect: () => [
        const SettingsState(
          defaultFocusMinutes: 45,
          errorMessage: AppStrings.invalidFocusDuration,
        ),
      ],
      verify: (_) => verifyNever(() => prefs.setInt(any(), any())),
    );
  }

  test(
    'real integer preferences survive a newly created cubit for every option',
    () async {
      SharedPreferences.setMockInitialValues({});
      final realPrefs = PrefsService(await SharedPreferences.getInstance());
      for (final minutes in [45, 15, 25]) {
        final cubit = SettingsCubit(realPrefs);
        await cubit.setFocusMinutes(minutes);
        expect(realPrefs.getInt(AppConstants.focusDurationKey), minutes);
        await cubit.close();
        final restored = SettingsCubit(realPrefs);
        expect(restored.state.defaultFocusMinutes, minutes);
        await restored.close();
      }
    },
  );

  test(
    'rapid selections serialize writes and leave the last persisted duration',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      final writes = <int>[];
      when(() => prefs.setInt(AppConstants.focusDurationKey, any()))
          .thenAnswer((invocation) async {
            writes.add(invocation.positionalArguments[1] as int);
            if (writes.length == 1) {
              started.complete();
              await gate.future;
            }
          });
      final cubit = SettingsCubit(prefs, initialMinutes: 25);
      final long = cubit.setFocusMinutes(45);
      final short = cubit.setFocusMinutes(15);
      await started.future;
      expect(writes, [45]);
      expect(
        cubit.state,
        const SettingsState(defaultFocusMinutes: 25, isSaving: true),
      );
      gate.complete();
      await Future.wait([long, short]);
      expect(writes, [45, 15]);
      expect(cubit.state, const SettingsState(defaultFocusMinutes: 15));
      await cubit.close();
    },
  );

  test('invalid queued request reports error against the newly saved valid duration', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    when(() => prefs.setInt(AppConstants.focusDurationKey, 45))
        .thenAnswer((_) async {
          started.complete();
          await gate.future;
        });
    final cubit = SettingsCubit(prefs, initialMinutes: 25);
    final valid = cubit.setFocusMinutes(45);
    final invalid = cubit.setFocusMinutes(99);
    await started.future;
    gate.complete();
    await Future.wait([valid, invalid]);
    expect(
      cubit.state,
      const SettingsState(
        defaultFocusMinutes: 45,
        errorMessage: AppStrings.invalidFocusDuration,
      ),
    );
    verify(() => prefs.setInt(AppConstants.focusDurationKey, 45)).called(1);
    verifyNever(() => prefs.setInt(AppConstants.focusDurationKey, 99));
    await cubit.close();
  });

  blocTest<SettingsCubit, SettingsState>(
    'next successful save clears the previous failure and the queue recovers',
    build: () {
      when(() => prefs.setInt(AppConstants.focusDurationKey, 45))
          .thenThrow(const StorageException());
      when(() => prefs.setInt(AppConstants.focusDurationKey, 15))
          .thenAnswer((_) async {});
      return SettingsCubit(prefs, initialMinutes: 25);
    },
    act: (cubit) async {
      await cubit.setFocusMinutes(45);
      await cubit.setFocusMinutes(15);
    },
    expect: () => [
      const SettingsState(defaultFocusMinutes: 25, isSaving: true),
      const SettingsState(
        defaultFocusMinutes: 25,
        errorMessage: AppStrings.storageError,
      ),
      const SettingsState(defaultFocusMinutes: 25, isSaving: true),
      const SettingsState(defaultFocusMinutes: 15),
    ],
  );

  test('close skips queued saves and prevents late state changes', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final writes = <int>[];
    when(() => prefs.setInt(AppConstants.focusDurationKey, any()))
        .thenAnswer((invocation) async {
          writes.add(invocation.positionalArguments[1] as int);
          started.complete();
          await gate.future;
        });
    final cubit = SettingsCubit(prefs, initialMinutes: 25);
    final first = cubit.setFocusMinutes(45);
    final queued = cubit.setFocusMinutes(15);
    await started.future;
    final stateAtClose = cubit.state;
    await cubit.close();
    gate.complete();
    await Future.wait([first, queued]);
    await cubit.setFocusMinutes(15);
    expect(writes, [45]);
    expect(cubit.state, stateAtClose);
  });
}
