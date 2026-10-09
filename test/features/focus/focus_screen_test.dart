import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/focus/cubit/timer_cubit.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_player_service.dart';

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _tick++;
    callback();
  }
}

class _Clock {
  DateTime current = DateTime(2026, 10, 12, 10);
  _ManualTimer? timer;
  DateTime now() => current;
  Timer periodic(Duration interval, void Function() callback) =>
      timer = _ManualTimer(callback);
  void advance(int seconds) {
    current = current.add(Duration(seconds: seconds));
    timer?.fire();
  }
}

class _MemoryHive extends HiveService {
  final _boxes = <String, Map<String, String>>{};
  bool failTaskWrite = false;
  bool failSessionAfterCommit = false;
  int sessionWrites = 0;
  Map<String, String> _box(String name) => _boxes.putIfAbsent(name, () => {});
  @override
  List<String> readAll(String boxName) => _box(boxName).values.toList();
  @override
  String? read(String boxName, String key) => _box(boxName)[key];
  @override
  Future<void> put(String boxName, String key, String json) async {
    if (boxName == AppConstants.tasksBox && failTaskWrite) {
      throw const StorageException();
    }
    _box(boxName)[key] = json;
    if (boxName == AppConstants.focusSessionsBox) {
      sessionWrites++;
      if (failSessionAfterCommit) {
        failSessionAfterCommit = false;
        throw const StorageException();
      }
    }
  }

  @override
  Future<void> delete(String boxName, String key) async {
    _box(boxName).remove(key);
  }

  @override
  Future<void> clear(String boxName) async {
    _box(boxName).clear();
  }
}

class _Fixture {
  _Fixture(
    this.hive,
    this.clock,
    this.tasks,
    this.focus,
    this.audio,
    this.service,
    this.settings,
    this.task,
  );
  final _MemoryHive hive;
  final _Clock clock;
  final TaskCubit tasks;
  final FocusRepository focus;
  final AudioCubit audio;
  final FakeAudioPlayerService service;
  final SettingsCubit settings;
  final TaskModel task;
  late TimerCubit timer;
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _dialogAction(String label) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(label));

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
  int? shortSeconds,
  ThemeData? theme,
  bool narrow = false,
  bool openFocus = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = narrow
      ? const Size(320, 568)
      : const Size(600, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({AppConstants.focusDurationKey: 45});
  final preferences = await SharedPreferences.getInstance();
  final hive = _MemoryHive();
  final clock = _Clock();
  final task = TaskModel(id: 'focus-task', title: 'Finish the meaningful task');
  final repository = TaskRepository(TaskLocalDatasource(hive), now: clock.now);
  await repository.addTask(task);
  final tasks = TaskCubit(repository);
  await tasks.load();
  final focus = FocusRepository(
    FocusLocalDatasource(hive),
    repository,
    now: clock.now,
  );
  final service = FakeAudioPlayerService();
  final audio = AudioCubit(const AudioRepository(), service);
  final settings = SettingsCubit(PrefsService(preferences));
  final fixture = _Fixture(
    hive,
    clock,
    tasks,
    focus,
    audio,
    service,
    settings,
    task,
  );
  addTearDown(tasks.close);
  addTearDown(audio.close);
  addTearDown(settings.close);
  await tester.pumpWidget(
    RepositoryProvider<FocusRepository>.value(
      value: focus,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TaskCubit>.value(value: tasks),
          BlocProvider<AudioCubit>.value(value: audio),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Fixture home'),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(Routes.focus),
                      child: const Text('Open focus'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(Routes.music),
                      child: const Text('Open music'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          onGenerateRoute: (route) => MaterialPageRoute<void>(
            settings: route,
            builder: (_) => route.name == Routes.music
                ? const MusicScreen()
                : FocusScreen(
                    task: task,
                    timerFactory: (repository, minutes) =>
                        fixture.timer = TimerCubit(
                          repository,
                          initialMinutes: minutes,
                          now: clock.now,
                          periodicTicker: clock.periodic,
                          secondsForMinutes: shortSeconds == null
                              ? null
                              : (_) => shortSeconds,
                        ),
                  ),
          ),
        ),
      ),
    ),
  );
  if (openFocus) await _tap(tester, find.text('Open focus'));
  return fixture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      '${theme.brightness.name}: narrow default, presets and timer controls work without automatic music',
      (tester) async {
        final fixture = await _launch(tester, theme: theme, narrow: true);
        expect(fixture.timer.state.selectedMinutes, 45);
        expect(fixture.timer.state.totalSeconds, 2700);
        expect(tester.widget<Text>(_key('focus-countdown')).data, '45:00');
        for (final minutes in [15, 25, 45]) {
          await _tap(tester, _key('focus-duration-$minutes'));
          expect(fixture.timer.state.totalSeconds, minutes * 60);
          expect(
            tester.widget<ChoiceChip>(_key('focus-duration-$minutes')).selected,
            isTrue,
          );
        }
        await _tap(tester, _key('focus-music-enabled'));
        expect(
          tester.widget<SwitchListTile>(_key('focus-music-enabled')).value,
          isFalse,
        );
        await _tap(tester, _key('focus-start'));
        expect(fixture.timer.state.status, TimerStatus.running);
        fixture.clock.advance(5);
        await _frames(tester);
        await _tap(tester, _key('focus-pause'));
        expect(fixture.timer.state.status, TimerStatus.paused);
        fixture.clock.advance(60);
        await _frames(tester);
        expect(fixture.timer.state.remainingSeconds, 2695);
        await _tap(tester, _key('focus-resume'));
        expect(fixture.timer.state.status, TimerStatus.running);
        await _tap(tester, _key('focus-reset'));
        expect(find.text(AppStrings.focusResetTitle), findsOneWidget);
        await _tap(tester, _dialogAction(AppStrings.cancel));
        expect(fixture.timer.state.status, TimerStatus.running);
        await _tap(tester, _key('focus-reset'));
        await _tap(tester, _dialogAction(AppStrings.reset));
        expect(fixture.timer.state.status, TimerStatus.idle);
        expect(fixture.timer.state.remainingSeconds, 2700);
        expect(await fixture.focus.getSessions(), isEmpty);
        expect(fixture.service.calls('play'), 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Music selection and decoder are shared with Focus and survive leaving its route',
    (tester) async {
      final fixture = await _launch(tester, openFocus: false);
      await _tap(tester, find.text('Open music'));
      final third = const AudioRepository().focusTracks[2];
      await _tap(tester, _key('audio-track-${third.id}'));
      fixture.service.emitPosition(const Duration(seconds: 7));
      await _frames(tester);
      await tester.pageBack();
      await _frames(tester);
      await _tap(tester, find.text('Open focus'));
      expect(find.text(third.title), findsOneWidget);
      expect(fixture.audio.state.currentIndex, 2);
      final loads = fixture.service.playlistLoads.length;
      await _tap(tester, _key('focus-start'));
      expect(fixture.audio.state.status, AppPlayerStatus.playing);
      expect(fixture.service.playlistLoads, hasLength(loads));
      expect(fixture.audio.state.currentIndex, 2);
      expect(fixture.audio.state.position, const Duration(seconds: 7));
      await tester.pageBack();
      await _frames(tester);
      await _tap(tester, _dialogAction(AppStrings.leave));
      await _frames(tester);
      expect(find.byType(FocusScreen), findsNothing);
      expect(find.text('Fixture home'), findsOneWidget);
      expect(fixture.timer.isClosed, isTrue);
      expect(fixture.audio.isClosed, isFalse);
      expect(fixture.service.disposed, isFalse);
      expect(fixture.audio.state.status, AppPlayerStatus.paused);
      expect(fixture.audio.state.currentIndex, 2);
      expect(fixture.audio.state.position, const Duration(seconds: 7));
      expect(await fixture.focus.getSessions(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['pause', 'finish', 'leave']) {
    testWidgets('delayed music initialization cannot autoplay after $action', (
      tester,
    ) async {
      final fixture = await _launch(
        tester,
        shortSeconds: action == 'finish' ? 3 : 60,
      );
      final gate = Completer<void>();
      fixture.service.gates['setPlaylist'] = gate;
      await _tap(tester, _key('focus-start'));
      expect(fixture.audio.state.isBusy, isTrue);
      expect(fixture.service.calls('play'), 0);
      if (action == 'pause') {
        await _tap(tester, _key('focus-pause'));
        expect(fixture.timer.state.status, TimerStatus.paused);
      } else if (action == 'finish') {
        fixture.clock.advance(3);
        await _frames(tester);
        expect(fixture.timer.state.status, TimerStatus.finished);
      } else {
        await tester.pageBack();
        await _frames(tester);
        await _tap(tester, _dialogAction(AppStrings.leave));
      }
      gate.complete();
      await _frames(tester);
      await _frames(tester);
      expect(fixture.service.calls('play'), 0);
      expect(fixture.audio.state.status, AppPlayerStatus.paused);
      if (action == 'finish') {
        expect(find.text(AppStrings.greatFocus), findsOneWidget);
        await _tap(tester, _dialogAction(AppStrings.no));
      } else if (action == 'leave') {
        expect(find.byType(FocusScreen), findsNothing);
        expect(fixture.service.disposed, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final markDone in [false, true]) {
    testWidgets(
      'natural completion saves once and ${markDone ? 'Yes completes' : 'No preserves'} the task',
      (tester) async {
        final fixture = await _launch(tester, shortSeconds: 3);
        await _tap(tester, _key('focus-start'));
        fixture.clock.advance(3);
        await _frames(tester);
        await _frames(tester);
        expect(find.text(AppStrings.greatFocus), findsOneWidget);
        expect(fixture.timer.state.lastSession!.completed, isTrue);
        expect(fixture.hive.sessionWrites, 1);
        await _tap(
          tester,
          _dialogAction(markDone ? AppStrings.yes : AppStrings.no),
        );
        expect(find.byType(Dialog), findsNothing);
        expect(fixture.tasks.state.tasks.single.isDone, markDone);
        expect((await fixture.focus.getSessions()).single.actualSeconds, 3);
        expect(fixture.hive.sessionWrites, 1);
        expect(fixture.audio.state.status, AppPlayerStatus.paused);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'task save failure stays in the completion dialog and Retry succeeds without another session',
    (tester) async {
      final fixture = await _launch(tester, shortSeconds: 3);
      fixture.hive.failTaskWrite = true;
      await _tap(tester, _key('focus-start'));
      fixture.clock.advance(3);
      await _frames(tester);
      await _frames(tester);
      await _tap(tester, _dialogAction(AppStrings.yes));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(AppStrings.storageError), findsOneWidget);
      expect(fixture.tasks.state.tasks.single.isDone, isFalse);
      expect(fixture.hive.sessionWrites, 1);
      fixture.hive.failTaskWrite = false;
      await _tap(tester, _dialogAction(AppStrings.retry));
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.tasks.state.tasks.single.isDone, isTrue);
      expect(await fixture.focus.getSessions(), hasLength(1));
      expect(fixture.hive.sessionWrites, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back Stay retains running work and Leave saves an active partial session',
    (tester) async {
      final fixture = await _launch(tester);
      await _tap(tester, _key('focus-music-enabled'));
      await _tap(tester, _key('focus-start'));
      fixture.clock.advance(6);
      await tester.pageBack();
      await _frames(tester);
      expect(find.text(AppStrings.leaveFocusTitle), findsOneWidget);
      await _tap(tester, _dialogAction(AppStrings.stay));
      expect(fixture.timer.state.status, TimerStatus.running);
      expect(await fixture.focus.getSessions(), isEmpty);
      fixture.clock.advance(5);
      await tester.pageBack();
      await _frames(tester);
      await _tap(tester, _dialogAction(AppStrings.leave));
      await _frames(tester);
      expect(find.byType(FocusScreen), findsNothing);
      final session = (await fixture.focus.getSessions()).single;
      expect(session.completed, isFalse);
      expect(session.actualSeconds, 11);
      expect(fixture.timer.isClosed, isTrue);
      expect(fixture.audio.isClosed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed session acknowledgement blocks Back until Retry accepts the exact committed session',
    (tester) async {
      final fixture = await _launch(tester, shortSeconds: 3);
      fixture.hive.failSessionAfterCommit = true;
      await _tap(tester, _key('focus-start'));
      fixture.clock.advance(3);
      await _frames(tester);
      final pending = fixture.timer.state.pendingSession!;
      expect(fixture.timer.state.errorMessage, AppStrings.storageError);
      expect(find.text(AppStrings.greatFocus), findsNothing);
      await tester.binding.handlePopRoute();
      await _frames(tester);
      expect(find.byType(FocusScreen), findsOneWidget);
      expect(fixture.timer.isClosed, isFalse);
      await _tap(tester, _key('focus-save-retry'));
      await _frames(tester);
      expect(find.text(AppStrings.greatFocus), findsOneWidget);
      await _tap(tester, _dialogAction(AppStrings.no));
      expect(fixture.timer.state.lastSession, pending);
      expect(fixture.timer.state.pendingSession, isNull);
      expect(await fixture.focus.getSessions(), [pending]);
      expect(fixture.hive.sessionWrites, 1);
      await tester.pageBack();
      await _frames(tester);
      await _frames(tester);
      expect(find.byType(FocusScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
