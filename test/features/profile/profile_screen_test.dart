import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_player_service.dart';

class _MemoryHive extends HiveService {
  final boxes = <String, Map<String, String>>{};
  bool failFocusClear = false;

  Map<String, String> _box(String name) => boxes.putIfAbsent(name, () => {});
  @override
  List<String> readAll(String boxName) => _box(boxName).values.toList();
  @override
  String? read(String boxName, String key) => _box(boxName)[key];
  @override
  Future<void> put(String boxName, String key, String json) async {
    _box(boxName)[key] = json;
  }

  @override
  Future<void> delete(String boxName, String key) async {
    _box(boxName).remove(key);
  }

  @override
  Future<void> clear(String boxName) async {
    if (boxName == AppConstants.focusSessionsBox && failFocusClear) {
      throw const StorageException();
    }
    _box(boxName).clear();
  }
}

class _Fixture {
  _Fixture(
    this.dependencies,
    this.preferences,
    this.hive,
    this.audio,
    this.playerCreations,
  );
  final AppDependencies dependencies;
  final SharedPreferences preferences;
  final _MemoryHive hive;
  final FakeAudioPlayerService audio;
  final int Function() playerCreations;
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Finder _navigation(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
Finder _key(String value) => find.byKey(ValueKey(value));
Finder _dialogAction(String label) => find.descendant(
  of: find.byType(Dialog),
  matching: find.widgetWithText(FilledButton, label),
);
Finder _nameField() => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == AppStrings.name,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await _frames(tester);
  }
  if (finder.hitTestable().evaluate().isEmpty &&
      find.byType(SnackBar).hitTestable().evaluate().isNotEmpty) {
    await tester.drag(
      find.byType(SnackBar).hitTestable(),
      const Offset(0, 150),
    );
    await _frames(tester);
  }
  await tester.tap(finder);
  await _frames(tester);
}

Future<_Fixture> _launch(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  bool narrow = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = narrow
      ? const Size(320, 568)
      : const Size(600, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  tester.platformDispatcher.textScaleFactorTestValue = narrow ? 1.3 : 1;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({
    AppConstants.sessionUserKey: 'demo-user',
    AppConstants.themeModeKey: mode.name,
    AppConstants.focusDurationKey: 25,
  });
  final preferences = await SharedPreferences.getInstance();
  final prefs = PrefsService(preferences);
  final hive = _MemoryHive();
  final task = TaskModel(id: 'profile-task', title: 'Keep until confirmed');
  await hive.put(AppConstants.tasksBox, task.id, jsonEncode(task.toJson()));
  await hive.put(
    AppConstants.focusSessionsBox,
    'session-1',
    '{"id":"session-1"}',
  );
  final audio = FakeAudioPlayerService();
  var playerCreations = 0;
  // Create queued production repositories inside this widget test's zone.
  final dependencies = AppDependencies(
    prefs: prefs,
    hive: hive,
    auth: AuthRepository(AuthLocalDatasource(prefs), delay: Duration.zero),
    audioPlayerFactory: () {
      playerCreations++;
      return audio;
    },
  );
  addTearDown(() => dependencies.dio.close(force: true));
  await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
  await tester.pump(AppConstants.splashDuration);
  await _frames(tester);
  expect(find.byType(HomeScreen), findsOneWidget);
  await _tap(tester, _navigation(AppStrings.profile));
  expect(find.byType(ProfileScreen), findsOneWidget);
  return _Fixture(
    dependencies,
    preferences,
    hive,
    audio,
    () => playerCreations,
  );
}

Future<void> _cancelDialog(WidgetTester tester) => _tap(
  tester,
  find.descendant(
    of: find.byType(Dialog),
    matching: find.widgetWithText(TextButton, AppStrings.cancel),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'edit name validates, cancels and persists a refreshed authenticated user',
    (tester) async {
      final fixture = await _launch(tester);
      final profile = find.byType(ProfileScreen);
      final auth = tester.element(profile).read<AuthCubit>();
      final original = (auth.state as Authenticated).user;
      expect(find.text(original.name), findsOneWidget);
      expect(find.text(original.email), findsOneWidget);
      expect(find.text('DU'), findsOneWidget);

      await _tap(tester, _key('profile-edit-name'));
      await tester.enterText(_nameField(), 'A');
      await _tap(tester, _dialogAction(AppStrings.save));
      expect(find.text(AppStrings.nameInvalid), findsOneWidget);
      expect((auth.state as Authenticated).user, original);
      await _cancelDialog(tester);
      expect(find.byType(Dialog), findsNothing);

      await _tap(tester, _key('profile-edit-name'));
      await tester.enterText(_nameField(), '  Updated Person  ');
      await _tap(tester, _dialogAction(AppStrings.save));
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Updated Person'), findsOneWidget);
      expect(find.text('UP'), findsOneWidget);
      final saved = (auth.state as Authenticated).user;
      expect(saved.id, original.id);
      expect(saved.email, original.email);
      expect(saved.name, 'Updated Person');
      expect(await fixture.dependencies.auth.currentUser(), saved);
      final records = jsonDecode(
        fixture.preferences.getString(AppConstants.usersKey)!,
      ) as List;
      expect(
        records.singleWhere(
          (dynamic entry) => entry['id'] == original.id,
        )['name'],
        saved.name,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'theme and focus selectors update the app and persisted choices live',
    (tester) async {
      final fixture = await _launch(tester);
      final profile = find.byType(ProfileScreen);
      final theme = tester.element(profile).read<ThemeCubit>();
      final settings = tester.element(profile).read<SettingsCubit>();
      for (final (label, mode) in [
        (AppStrings.darkTheme, ThemeMode.dark),
        (AppStrings.lightTheme, ThemeMode.light),
        (AppStrings.systemTheme, ThemeMode.system),
      ]) {
        await _tap(
          tester,
          find.descendant(
            of: _key('profile-theme'),
            matching: find.text(label),
          ),
        );
        expect(theme.state.mode, mode);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          mode,
        );
        expect(
          fixture.preferences.getString(AppConstants.themeModeKey),
          mode.name,
        );
      }
      for (final minutes in [45, 15, 25]) {
        await _tap(
          tester,
          find.descendant(
            of: _key('profile-focus-duration'),
            matching: find.text(AppStrings.minutes(minutes)),
          ),
        );
        expect(settings.state.defaultFocusMinutes, minutes);
        expect(
          fixture.preferences.getInt(AppConstants.focusDurationKey),
          minutes,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear confirmation cancels safely then clears tasks and focus while retaining account',
    (tester) async {
      final fixture = await _launch(tester, mode: ThemeMode.dark);
      final profile = find.byType(ProfileScreen);
      final auth = tester.element(profile).read<AuthCubit>();
      final tasks = tester.element(profile).read<TaskCubit>();
      final user = (auth.state as Authenticated).user;
      final accounts = fixture.preferences.getString(AppConstants.usersKey);
      await _tap(tester, _key('profile-clear-data'));
      expect(find.text(AppStrings.clearDataTitle), findsOneWidget);
      await _cancelDialog(tester);
      expect(fixture.hive.readAll(AppConstants.tasksBox), hasLength(1));
      expect(fixture.hive.readAll(AppConstants.focusSessionsBox), hasLength(1));
      await _tap(tester, _key('profile-clear-data'));
      await _tap(tester, _dialogAction(AppStrings.clearData));
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.hive.readAll(AppConstants.tasksBox), isEmpty);
      expect(fixture.hive.readAll(AppConstants.focusSessionsBox), isEmpty);
      expect(tasks.state.tasks, isEmpty);
      expect(tasks.state.lastDeleted, isNull);
      expect(auth.state, Authenticated(user));
      expect(
        fixture.preferences.getString(AppConstants.sessionUserKey),
        user.id,
      );
      expect(fixture.preferences.getString(AppConstants.usersKey), accounts);
      expect(fixture.preferences.getString(AppConstants.themeModeKey), 'dark');
      expect(fixture.preferences.getInt(AppConstants.focusDurationKey), 25);
      expect(await fixture.dependencies.auth.currentUser(), user);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear failure stays friendly, refreshes partial changes and allows another attempt',
    (tester) async {
      final fixture = await _launch(tester);
      fixture.hive.failFocusClear = true;
      await _tap(tester, _key('profile-clear-data'));
      await _tap(tester, _dialogAction(AppStrings.clearData));
      expect(find.text(AppStrings.storageError), findsWidgets);
      expect(fixture.hive.readAll(AppConstants.tasksBox), isEmpty);
      expect(fixture.hive.readAll(AppConstants.focusSessionsBox), hasLength(1));
      expect(
        tester
            .element(find.byType(ProfileScreen))
            .read<TaskCubit>()
            .state
            .tasks,
        isEmpty,
      );
      expect(
        fixture.preferences.getString(AppConstants.sessionUserKey),
        isNotNull,
      );
      fixture.hive.failFocusClear = false;
      await _tap(tester, _key('profile-clear-data'));
      await _tap(tester, _dialogAction(AppStrings.clearData));
      expect(fixture.hive.readAll(AppConstants.focusSessionsBox), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logout cancellation keeps playback and confirmed logout stops it and clears the route stack',
    (tester) async {
      final fixture = await _launch(tester);
      final accounts = fixture.preferences.getString(AppConstants.usersKey);
      await _tap(tester, _navigation(AppStrings.music));
      final audio = tester.element(find.byType(MusicScreen)).read<AudioCubit>();
      await _tap(tester, _key('audio-play-pause'));
      expect(audio.state.status, AppPlayerStatus.playing);
      await _tap(tester, _navigation(AppStrings.profile));
      final pauseCalls = fixture.audio.calls('pause');
      await _tap(tester, _key('profile-logout'));
      await _cancelDialog(tester);
      expect(audio.state.status, AppPlayerStatus.playing);
      expect(fixture.audio.calls('pause'), pauseCalls);
      expect(
        fixture.preferences.getString(AppConstants.sessionUserKey),
        isNotNull,
      );
      await _tap(tester, _key('profile-logout'));
      await _tap(tester, _dialogAction(AppStrings.logout));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        isFalse,
      );
      expect(
        fixture.preferences.getString(AppConstants.sessionUserKey),
        isNull,
      );
      expect(fixture.preferences.getString(AppConstants.usersKey), accounts);
      expect(audio.state.status, AppPlayerStatus.paused);
      expect(fixture.audio.calls('pause'), greaterThan(pauseCalls));
      expect(audio.state.position, Duration.zero);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile logout never creates an unused audio decoder', (
    tester,
  ) async {
    final fixture = await _launch(tester);
    expect(fixture.playerCreations(), 0);
    await _tap(tester, _key('profile-logout'));
    await _tap(tester, _dialogAction(AppStrings.logout));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(fixture.playerCreations(), 0);
    expect(fixture.audio.operations, isEmpty);
    expect(fixture.preferences.getString(AppConstants.sessionUserKey), isNull);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '${mode.name}: 320px enlarged profile and edit dialog remain usable',
      (tester) async {
        await _launch(tester, mode: mode, narrow: true);
        expect(find.text(AppConstants.demoEmail), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byType(ProfileScreen))).brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        );
        await _tap(tester, _key('profile-edit-name'));
        await tester.enterText(_nameField(), 'Responsive User');
        await _tap(tester, _dialogAction(AppStrings.save));
        expect(find.text('Responsive User'), findsOneWidget);
        await _tap(
          tester,
          find.descendant(
            of: _key('profile-focus-duration'),
            matching: find.text(AppStrings.minutes(45)),
          ),
        );
        await _tap(tester, _key('profile-clear-data'));
        await _cancelDialog(tester);
        await _tap(tester, _key('profile-logout'));
        await _cancelDialog(tester);
        expect(find.text(AppStrings.about), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
