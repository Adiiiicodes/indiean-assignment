import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';

Matcher get _storageFailure => isA<StorageException>()
    .having(
      (error) => error.message,
      'friendly message',
      AppStrings.storageError,
    )
    .having(
      (error) => error.toString(),
      'private details',
      isNot(contains('test-secret')),
    );

void main() {
  late Directory directory;
  late HiveService hive;
  late TaskRepository repository;
  late DateTime now;
  final created = DateTime.utc(2026, 10, 12, 8);
  final task = TaskModel(
    id: 'task-1',
    title: 'Prepare the assignment',
    description: 'Draft an outline.\nCheck the examples.',
    priority: TaskPriority.high,
    dueDate: DateTime.utc(2026, 10, 14),
    isDone: false,
    createdAt: created,
    updatedAt: created.add(const Duration(minutes: 10)),
    source: TaskSource.imported,
  );

  setUp(() async {
    await Hive.close();
    directory = await Directory.systemTemp.createTemp(
      'focusdesk_task_repository_',
    );
    hive = HiveService(hive: Hive);
    await hive.init(path: directory.path);
    now = DateTime.utc(2026, 10, 12, 9);
    repository = TaskRepository(TaskLocalDatasource(hive), now: () => now);
  });

  tearDown(() async {
    await Hive.close();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    expect(target.startsWith('$tempRoot${Platform.pathSeparator}'), isTrue);
    await directory.delete(recursive: true);
  });

  test('empty repository returns no tasks and null for a missing ID', () async {
    expect(await repository.getTasks(), isEmpty);
    expect(await repository.getById('missing'), isNull);
  });

  test('add persists every field as JSON keyed by the exact task ID', () async {
    expect(await repository.addTask(task), task);
    expect(await repository.getById(task.id), task);
    expect(await repository.getTasks(), [task]);
    final encoded = hive.read(AppConstants.tasksBox, task.id)!;
    expect(jsonDecode(encoded), task.toJson());
  });

  test('newest creation comes first and equal timestamps sort by ID', () async {
    final oldest = task.copyWith(
      id: 'oldest',
      createdAt: created.subtract(const Duration(days: 1)),
    );
    final tiedZ = task.copyWith(id: 'z-task');
    final tiedA = task.copyWith(id: 'a-task');
    final newest = task.copyWith(
      id: 'newest',
      createdAt: created.add(const Duration(days: 1)),
    );
    for (final item in [tiedZ, newest, oldest, tiedA]) {
      await repository.addTask(item);
    }
    expect(await repository.getTasks(), [newest, tiedA, tiedZ, oldest]);
    expect(await repository.getTasks(), [newest, tiedA, tiedZ, oldest]);
  });

  test(
    'update changes task fields while preserving identity and creation time',
    () async {
      await repository.addTask(task);
      final edited = task.copyWith(
        title: 'Read one chapter',
        description: 'Take notes.',
        priority: TaskPriority.low,
        clearDueDate: true,
        isDone: true,
        source: TaskSource.local,
        createdAt: DateTime(1900),
        updatedAt: DateTime(1900),
      );
      final saved = await repository.updateTask(edited);
      expect(saved, edited.copyWith(createdAt: task.createdAt, updatedAt: now));
      expect(saved.id, task.id);
      expect(saved.createdAt, created);
      expect(saved.updatedAt.isAfter(task.updatedAt), isTrue);
      expect(await repository.getById(task.id), saved);
      expect(task.title, 'Prepare the assignment');
      expect(task.isDone, isFalse);
    },
  );

  test(
    'toggleDone works in both directions and advances only update time',
    () async {
      await repository.addTask(task);
      final done = await repository.toggleDone(task.id);
      expect(done, task.copyWith(isDone: true, updatedAt: now));
      now = now.add(const Duration(minutes: 5));
      final pending = await repository.toggleDone(task.id);
      expect(pending, task.copyWith(isDone: false, updatedAt: now));
      expect(pending.updatedAt.isAfter(done.updatedAt), isTrue);
      expect(await repository.getById(task.id), pending);
    },
  );

  test(
    'delete preserves siblings and restore reinstates the exact snapshot',
    () async {
      final sibling = task.copyWith(id: 'task-2', title: 'Keep this task');
      await repository.addTask(task);
      await repository.addTask(sibling);
      await repository.deleteTask(task.id);
      expect(await repository.getById(task.id), isNull);
      expect(await repository.getTasks(), [sibling]);
      expect(await repository.restoreTask(task), task);
      expect(await repository.getById(task.id), task);
      expect(await repository.getById(sibling.id), sibling);
      expect(
        jsonDecode(hive.read(AppConstants.tasksBox, task.id)!),
        task.toJson(),
      );
    },
  );

  test(
    'duplicate add and conflicting restore reject without overwriting',
    () async {
      await repository.addTask(task);
      final snapshot = hive.read(AppConstants.tasksBox, task.id);
      final conflicting = task.copyWith(title: 'Would overwrite the original');
      await expectLater(
        repository.addTask(conflicting),
        throwsA(_storageFailure),
      );
      await expectLater(
        repository.restoreTask(conflicting),
        throwsA(_storageFailure),
      );
      expect(hive.read(AppConstants.tasksBox, task.id), snapshot);
      expect(await repository.getById(task.id), task);
    },
  );

  test(
    'missing update/toggle fail and deleting a missing ID is idempotent',
    () async {
      await repository.addTask(task);
      await expectLater(
        repository.updateTask(task.copyWith(id: 'missing')),
        throwsA(_storageFailure),
      );
      await expectLater(
        repository.toggleDone('missing'),
        throwsA(_storageFailure),
      );
      await repository.deleteTask('missing');
      expect(await repository.getTasks(), [task]);
    },
  );

  test(
    'concurrent duplicate adds do not overwrite and paired toggles both apply',
    () async {
      await Future.wait<dynamic>([
        repository.addTask(task),
        expectLater(
          repository.addTask(task.copyWith(title: 'Conflicting task')),
          throwsA(_storageFailure),
        ),
      ]);
      expect(await repository.getById(task.id), task);
      now = now.add(const Duration(minutes: 5));
      final toggled = await Future.wait([
        repository.toggleDone(task.id),
        repository.toggleDone(task.id),
      ]);
      expect(toggled.map((item) => item.isDone), [true, false]);
      expect(await repository.getById(task.id), task.copyWith(updatedAt: now));
    },
  );

  test(
    'clearAll removes tasks while leaving focus-session storage intact',
    () async {
      await repository.addTask(task);
      const session = '{"id":"session-1","minutes":25}';
      await hive.put(AppConstants.focusSessionsBox, 'session-1', session);
      await repository.clearAll();
      expect(await repository.getTasks(), isEmpty);
      expect(await repository.getById(task.id), isNull);
      expect(hive.read(AppConstants.focusSessionsBox, 'session-1'), session);
    },
  );

  test(
    'tasks survive real Hive close and initialization in a fresh repository',
    () async {
      final second = task.copyWith(
        id: 'task-2',
        isDone: true,
        createdAt: created.add(const Duration(days: 1)),
      );
      await repository.addTask(task);
      await repository.addTask(second);
      await hive.close();
      hive = HiveService(hive: Hive);
      await hive.init(path: directory.path);
      repository = TaskRepository(TaskLocalDatasource(hive), now: () => now);
      expect(await repository.getTasks(), [second, task]);
      expect(await repository.getById(task.id), task);
      expect(await repository.getById(second.id), second);
    },
  );

  test(
    'malformed JSON or invalid stored identities fail without data loss',
    () async {
      await repository.addTask(task);
      final validSnapshot = hive.read(AppConstants.tasksBox, task.id);
      for (final corrupted in [
        'not-json test-secret',
        '[]',
        'null',
        '{"title":"Missing identity"}',
        '{"id":"   "}',
        '{"id":"different-key"}',
      ]) {
        await hive.put(AppConstants.tasksBox, 'broken', corrupted);
        await expectLater(repository.getTasks(), throwsA(_storageFailure));
        await expectLater(
          repository.getById('broken'),
          throwsA(_storageFailure),
        );
        await expectLater(
          repository.updateTask(task.copyWith(id: 'broken')),
          throwsA(_storageFailure),
        );
        expect(hive.read(AppConstants.tasksBox, 'broken'), corrupted);
        expect(hive.read(AppConstants.tasksBox, task.id), validSnapshot);
      }
    },
  );

  test(
    'valid stored identity allows safe model defaults without rewriting',
    () async {
      final raw = jsonEncode({
        'id': 'recoverable',
        'title': false,
        'priority': 'urgent',
        'dueDate': true,
        'source': 12,
        'createdAt': created.toIso8601String(),
      });
      await hive.put(AppConstants.tasksBox, 'recoverable', raw);
      final recovered = (await repository.getById('recoverable'))!;
      expect(recovered.id, 'recoverable');
      expect(recovered.title, AppStrings.untitledTask);
      expect(recovered.priority, TaskPriority.medium);
      expect(recovered.dueDate, isNull);
      expect(recovered.source, TaskSource.local);
      expect(recovered.createdAt, created);
      expect(hive.read(AppConstants.tasksBox, 'recoverable'), raw);
    },
  );

  test(
    'closed storage maps every operation to a friendly StorageException',
    () async {
      await hive.close();
      final operations = <Future<dynamic> Function()>[
        repository.getTasks,
        () => repository.getById(task.id),
        () => repository.addTask(task),
        () => repository.updateTask(task),
        () => repository.toggleDone(task.id),
        () => repository.deleteTask(task.id),
        () => repository.restoreTask(task),
        repository.clearAll,
      ];
      for (final operation in operations) {
        await expectLater(operation(), throwsA(_storageFailure));
      }
    },
  );
}
