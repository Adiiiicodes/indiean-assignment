import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/focus/cubit/timer_cubit.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

class _CommitThenFailHive extends HiveService {
  _CommitThenFailHive() : super(hive: Hive);
  bool failAfterCommit = true;
  int writes = 0;
  @override
  Future<void> put(String boxName, String key, String json) async {
    await super.put(boxName, key, json);
    if (boxName == AppConstants.focusSessionsBox) {
      writes++;
      if (failAfterCommit) {
        failAfterCommit = false;
        throw const StorageException();
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HiveService hive;
  late _Clock clock;
  late TaskRepository tasks;
  final task = TaskModel(id: 'timer-task', title: 'Persistent focus target');

  setUp(() async {
    await Hive.close();
    directory = await Directory.systemTemp.createTemp(
      'focusdesk_timer_storage_',
    );
    hive = HiveService(hive: Hive);
    await hive.init(path: directory.path);
    clock = _Clock();
    tasks = TaskRepository(TaskLocalDatasource(hive), now: clock.now);
    await tasks.addTask(task);
  });

  tearDown(() async {
    await Hive.close();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    expect(target.startsWith('$root${Platform.pathSeparator}'), isTrue);
    await directory.delete(recursive: true);
  });

  FocusRepository repository({HiveService? storage}) => FocusRepository(
    FocusLocalDatasource(storage ?? hive),
    tasks,
    now: clock.now,
  );

  TimerCubit timer(FocusRepository repository, {int seconds = 60}) {
    final cubit = TimerCubit(
      repository,
      initialMinutes: 25,
      now: clock.now,
      periodicTicker: clock.periodic,
      secondsForMinutes: (_) => seconds,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  test('natural completion persists its task snapshot and survives close and Hive reopen', () async {
    final focus = repository();
    final cubit = timer(focus, seconds: 3);
    final started = clock.current;
    expect(cubit.start(task), isTrue);
    final saved = cubit.stream.firstWhere(
      (state) =>
          state.status == TimerStatus.finished &&
          !state.isSaving &&
          state.lastSession != null,
    );
    clock.advance(3);
    await saved.timeout(const Duration(seconds: 3));
    final session = cubit.state.lastSession!;
    expect(cubit.state.errorMessage, isNull);
    expect(cubit.state.pendingSession, isNull);
    expect(session.taskId, task.id);
    expect(session.taskTitle, task.title);
    expect(session.plannedMinutes, 25);
    expect(session.actualSeconds, 3);
    expect(session.completed, isTrue);
    expect(session.startedAt, started);
    expect(session.endedAt, clock.current);
    expect(await focus.getSessions(), [session]);
    expect(clock.timer!.isActive, isFalse);
    await cubit.close();
    await hive.close();
    hive = HiveService(hive: Hive);
    await hive.init(path: directory.path);
    final reopened = FocusRepository(
      FocusLocalDatasource(hive),
      TaskRepository(TaskLocalDatasource(hive)),
      now: clock.now,
    );
    expect(await reopened.getSessions(), [session]);
    expect(await reopened.sessionsForDay(started), [session]);
  });

  test(
    'partial logging counts active segments while excluding a long paused gap',
    () async {
      final focus = repository();
      final cubit = timer(focus);
      final started = clock.current;
      expect(cubit.start(task), isTrue);
      clock.advance(6);
      expect(cubit.pause(), isTrue);
      clock.advance(120);
      expect(cubit.resume(), isTrue);
      clock.advance(5);
      expect(await cubit.finishEarly(), isTrue);
      final session = cubit.state.lastSession!;
      expect(session.completed, isFalse);
      expect(session.actualSeconds, 11);
      expect(session.endedAt.difference(started).inSeconds, 131);
      expect(await focus.getSessions(), [session]);
      expect((await focus.todayStats()).sessionsToday, 1);
      expect(clock.timer!.isActive, isFalse);
    },
  );

  test('exactly ten active seconds with paused time does not create a partial record', () async {
    final focus = repository();
    final cubit = timer(focus);
    expect(cubit.start(task), isTrue);
    clock.advance(5);
    cubit.pause();
    clock.advance(600);
    cubit.resume();
    clock.advance(5);
    expect(await cubit.finishEarly(), isTrue);
    expect(cubit.state.status, TimerStatus.finished);
    expect(cubit.state.lastSession, isNull);
    expect(cubit.state.pendingSession, isNull);
    expect(await focus.getSessions(), isEmpty);
    expect(hive.readAll(AppConstants.focusSessionsBox), isEmpty);
  });

  test('a save failure after Hive commits keeps the UUID and retry never duplicates disk data', () async {
    final failing = _CommitThenFailHive();
    final focus = repository(storage: failing);
    final cubit = timer(focus, seconds: 3);
    expect(cubit.start(task), isTrue);
    final failed = cubit.stream.firstWhere(
      (state) => state.errorMessage != null && !state.isSaving,
    );
    clock.advance(3);
    await failed.timeout(const Duration(seconds: 3));
    expect(cubit.state.errorMessage, AppStrings.storageError);
    final pending = cubit.state.pendingSession!;
    expect(await focus.getSessions(), [pending]);
    expect(failing.writes, 1);
    expect(cubit.reset(), isFalse);
    expect(cubit.start(task), isFalse);
    expect(await cubit.retrySave(), isTrue);
    expect(cubit.state.pendingSession, isNull);
    expect(cubit.state.lastSession, pending);
    expect(cubit.state.errorMessage, isNull);
    expect(await focus.getSessions(), [pending]);
    expect(failing.writes, 1);
    expect(hive.readAll(AppConstants.focusSessionsBox), hasLength(1));
  });
}
