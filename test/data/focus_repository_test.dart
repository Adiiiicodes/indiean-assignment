import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';

class _ControlledDatasource extends FocusLocalDatasource {
  _ControlledDatasource() : super(HiveService());
  final records = <String, FocusSessionModel>{};
  Completer<void>? putGate;
  bool failPut = false;
  int putCalls = 0;
  @override
  Future<List<FocusSessionModel>> getSessions() async =>
      records.values.toList();
  @override
  Future<FocusSessionModel?> getById(String id) async => records[id];
  @override
  Future<void> put(FocusSessionModel session) async {
    putCalls++;
    await putGate?.future;
    if (failPut) throw StateError('private-path-secret');
    records[session.id] = session;
  }

  @override
  Future<void> clear() async => records.clear();
}

void main() {
  late Directory directory;
  late HiveService hive;
  late TaskRepository tasks;
  late FocusLocalDatasource datasource;
  late FocusRepository repository;
  late DateTime now;

  FocusSessionModel session(
    String id,
    DateTime start, {
    int seconds = 120,
    bool completed = false,
  }) => FocusSessionModel(
    id: id,
    taskId: 'task-$id',
    taskTitle: 'Work on $id',
    plannedMinutes: 25,
    actualSeconds: seconds,
    completed: completed,
    startedAt: start,
    endedAt: start.add(Duration(seconds: seconds)),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'focusdesk_focus_repository_',
    );
    hive = HiveService();
    await hive.close();
    await hive.init(path: directory.path);
    tasks = TaskRepository(TaskLocalDatasource(hive));
    datasource = FocusLocalDatasource(hive);
    now = DateTime(2026, 10, 10, 12);
    repository = FocusRepository(datasource, tasks, now: () => now);
  });

  tearDown(() async {
    await hive.close();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    expect(target.startsWith('$tempRoot${Platform.pathSeparator}'), isTrue);
    await directory.delete(recursive: true);
  });

  test('empty sessions and stats are immutable zero values', () async {
    expect(await repository.getSessions(), isEmpty);
    expect(await datasource.getById('missing'), isNull);
    expect(await repository.todayStats(), const FocusStats());
    final sessions = await repository.getSessions();
    expect(() => sessions.add(session('x', now)), throwsUnsupportedError);
  });

  test(
    'all fields persist and restore after actual Hive close/reopen',
    () async {
      final original = session(
        'one',
        now.toUtc(),
        seconds: 1500,
        completed: true,
      );
      expect(await repository.addSession(original), original);
      expect(
        jsonDecode(hive.read(AppConstants.focusSessionsBox, original.id)!),
        original.toJson(),
      );
      await hive.close();
      await hive.init(path: directory.path);
      final restored = FocusRepository(
        FocusLocalDatasource(hive),
        tasks,
        now: () => now,
      );
      expect(await restored.getSessions(), [original]);
      expect(
        await restored.todayStats(),
        const FocusStats(
          sessionsToday: 1,
          focusMinutesToday: 25,
          currentStreakDays: 1,
        ),
      );
    },
  );

  test(
    'newest first with deterministic ID tie order and immutable day lists',
    () async {
      final old = session('old', DateTime(2026, 10, 9));
      final a = session('a', now);
      final z = session('z', now);
      for (final value in [z, old, a]) {
        await repository.addSession(value);
      }
      expect(await repository.getSessions(), [a, z, old]);
      final today = await repository.sessionsForDay(now.toUtc());
      expect(today, [a, z]);
      expect(() => today.clear(), throwsUnsupportedError);
    },
  );

  test(
    'local start day owns UTC records and cross-midnight sessions',
    () async {
      final midnight = DateTime(2026, 10, 10);
      final before = session(
        'before',
        midnight.subtract(const Duration(seconds: 30)).toUtc(),
        seconds: 90,
      );
      final first = session('first', midnight.toUtc(), seconds: 30);
      final last = session(
        'last',
        DateTime(2026, 10, 10, 23, 59, 59).toUtc(),
        seconds: 90,
      );
      final next = session('next', DateTime(2026, 10, 11).toUtc());
      for (final value in [before, first, last, next]) {
        await repository.addSession(value);
      }
      expect(await repository.sessionsForDay(now), [last, first]);
      expect(
        await repository.sessionsForDay(
          midnight.subtract(const Duration(days: 1)),
        ),
        [before],
      );
      expect((await repository.todayStats()).focusMinutesToday, 2);
    },
  );

  test('partial seconds aggregate before flooring minutes; done tasks use updated day', () async {
    for (final value in [
      session('a', now, seconds: 35),
      session('b', now, seconds: 35),
      session('zero', now, seconds: 0),
    ]) {
      await repository.addSession(value);
    }
    await tasks.addTask(
      TaskModel(
        id: 'today-done',
        title: 'Done today',
        isDone: true,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: now.toUtc(),
      ),
    );
    await tasks.addTask(
      TaskModel(
        id: 'old-done',
        title: 'Done yesterday',
        isDone: true,
        updatedAt: DateTime(2026, 10, 9, 23, 59).toUtc(),
      ),
    );
    await tasks.addTask(
      TaskModel(id: 'pending', title: 'Pending today', updatedAt: now),
    );
    expect(
      await repository.todayStats(),
      const FocusStats(
        sessionsToday: 3,
        focusMinutesToday: 1,
        tasksCompletedToday: 1,
        currentStreakDays: 1,
      ),
    );
  });

  test(
    'streak counts unique positive days from today and stops at gaps',
    () async {
      for (final value in [
        session('today-a', now),
        session('today-b', now),
        session('yesterday', DateTime(2026, 10, 9)),
        session('two-days', DateTime(2026, 10, 8)),
        session('gap-zero', DateTime(2026, 10, 7), seconds: 0),
        session('older', DateTime(2026, 10, 6)),
        session('future', DateTime(2026, 10, 11)),
      ]) {
        await repository.addSession(value);
      }
      expect((await repository.todayStats()).currentStreakDays, 3);
      now = DateTime(2026, 10, 12);
      expect((await repository.todayStats()).currentStreakDays, 4);
      now = DateTime(2026, 10, 13);
      expect((await repository.todayStats()).currentStreakDays, 0);
    },
  );

  test('streak anchors yesterday and traverses leap/month/year calendar boundaries', () async {
    now = DateTime(2024, 3, 1, 12);
    for (final value in [
      session('feb29', DateTime(2024, 2, 29)),
      session('feb28', DateTime(2024, 2, 28)),
    ]) {
      await repository.addSession(value);
    }
    expect((await repository.todayStats()).currentStreakDays, 2);
    await repository.clearAll();
    now = DateTime(2027, 1, 1, 12);
    for (final value in [
      session('jan1', now),
      session('dec31', DateTime(2026, 12, 31)),
      session('dec30', DateTime(2026, 12, 30)),
    ]) {
      await repository.addSession(value);
    }
    expect((await repository.todayStats()).currentStreakDays, 3);
  });

  test(
    'zero-only and future-only sessions do not start a current streak',
    () async {
      await repository.addSession(session('zero', now, seconds: 0));
      await repository.addSession(session('future', DateTime(2026, 10, 11)));
      final stats = await repository.todayStats();
      expect(stats.sessionsToday, 1);
      expect(stats.focusMinutesToday, 0);
      expect(stats.currentStreakDays, 0);
    },
  );

  test('same snapshot retry is idempotent and conflicting duplicate cannot overwrite', () async {
    final original = session('one', now);
    final results = await Future.wait([
      repository.addSession(original),
      repository.addSession(original),
    ]);
    expect(results, [original, original]);
    expect(await repository.getSessions(), [original]);
    await expectLater(
      repository.addSession(original.copyWith(actualSeconds: 60)),
      throwsA(isA<StorageException>()),
    );
    expect(await repository.getSessions(), [original]);
    await repository.addSession(session('two', now));
    expect((await repository.getSessions()).length, 2);
  });

  test(
    'clear focus history preserves tasks and task-derived completion stats',
    () async {
      await tasks.addTask(
        TaskModel(
          id: 'done',
          title: 'Keep this task',
          isDone: true,
          updatedAt: now,
        ),
      );
      await repository.addSession(session('one', now));
      await repository.clearAll();
      expect(await repository.getSessions(), isEmpty);
      expect((await tasks.getTasks()).single.id, 'done');
      expect(
        await repository.todayStats(),
        const FocusStats(tasksCompletedToday: 1),
      );
    },
  );

  final malformed = <String, String>{
    'invalid JSON': '{private-secret',
    'nonobject': '[]',
    'missing fields': '{"id":"bad"}',
    'invalid type': jsonEncode(
      session('bad', DateTime(2026, 10, 10)).toJson()..['completed'] = 1,
    ),
    'invalid chronology': jsonEncode(
      session('bad', DateTime(2026, 10, 10)).toJson()
        ..['endedAt'] = '2026-10-09T00:00:00',
    ),
    'key identity mismatch': jsonEncode(
      session('other-id', DateTime(2026, 10, 10)).toJson(),
    ),
  };
  for (final entry in malformed.entries) {
    test(
      '${entry.key} maps to friendly StorageException without overwriting',
      () async {
        await hive.put(AppConstants.focusSessionsBox, 'bad', entry.value);
        final failure = isA<StorageException>().having(
          (e) => e.message,
          'message',
          AppStrings.storageError,
        );
        await expectLater(repository.getSessions(), throwsA(failure));
        await expectLater(datasource.getById('bad'), throwsA(failure));
        await expectLater(
          repository.addSession(session('bad', now)),
          throwsA(failure),
        );
        expect(hive.read(AppConstants.focusSessionsBox, 'bad'), entry.value);
      },
    );
  }

  test(
    'closed storage maps reads, writes and stats to friendly failures',
    () async {
      await hive.close();
      await expectLater(
        repository.getSessions(),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        repository.addSession(session('one', now)),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        repository.todayStats(),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        repository.clearAll(),
        throwsA(isA<StorageException>()),
      );
    },
  );

  test(
    'reads and clear wait behind an in-flight write, with safe failure retry',
    () async {
      final controlled = _ControlledDatasource();
      final queued = FocusRepository(controlled, tasks, now: () => now);
      final original = session('one', now);
      controlled.putGate = Completer<void>();
      final write = queued.addSession(original);
      final snapshot = queued.getSessions();
      var readCompleted = false;
      snapshot.then((_) => readCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(controlled.putCalls, 1);
      expect(readCompleted, isFalse);
      controlled.putGate!.complete();
      expect(await write, original);
      expect(await snapshot, [original]);

      controlled.putGate = Completer<void>();
      final another = queued.addSession(session('two', now));
      final clear = queued.clearAll();
      await Future<void>.delayed(Duration.zero);
      expect(controlled.records.keys, ['one']);
      controlled.putGate!.complete();
      await another;
      await clear;
      expect(await queued.getSessions(), isEmpty);

      controlled.putGate = null;
      controlled.failPut = true;
      await expectLater(
        queued.addSession(original),
        throwsA(
          isA<StorageException>().having(
            (e) => e.message,
            'private details',
            AppStrings.storageError,
          ),
        ),
      );
      controlled.failPut = false;
      expect(await queued.addSession(original), original);
    },
  );
}
