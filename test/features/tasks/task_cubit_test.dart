import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';

final _clock = DateTime.utc(2026, 10, 13);
final _first = TaskModel(
  id: 'first',
  title: 'Write report',
  description: 'Quarterly notes',
  priority: TaskPriority.high,
  createdAt: DateTime.utc(2026, 10, 12, 3),
);
final _second = TaskModel(
  id: 'second',
  title: 'Read chapter',
  description: 'Architecture NOTES',
  priority: TaskPriority.low,
  isDone: true,
  createdAt: DateTime.utc(2026, 10, 12, 2),
);
final _third = TaskModel(
  id: 'third',
  title: 'Plan launch',
  description: 'Public presentation',
  priority: TaskPriority.high,
  createdAt: DateTime.utc(2026, 10, 12, 1),
);
final _new = TaskModel(
  id: 'new',
  title: 'New focus task',
  description: 'Meeting notes',
  priority: TaskPriority.low,
  createdAt: DateTime.utc(2026, 10, 13),
);

class _FakeTaskRepository extends TaskRepository {
  _FakeTaskRepository([List<TaskModel> initial = const []])
    : stored = {for (final task in initial) task.id: task},
      super(TaskLocalDatasource(HiveService()));

  final Map<String, TaskModel> stored;
  final Map<String, Object> failures = {};
  final Map<String, int> calls = {};
  Completer<List<TaskModel>>? nextLoad;
  Completer<void>? nextWrite;

  void _call(String operation) {
    calls[operation] = (calls[operation] ?? 0) + 1;
    final error = failures[operation];
    if (error != null) {
      throw error;
    }
  }

  Future<void> _writeGate() async {
    final pending = nextWrite;
    nextWrite = null;
    await pending?.future;
  }

  @override
  Future<List<TaskModel>> getTasks() async {
    final pending = nextLoad;
    nextLoad = null;
    _call('load');
    if (pending != null) {
      return pending.future;
    }
    return stored.values.toList()..sort((a, b) {
      final order = b.createdAt.compareTo(a.createdAt);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  }

  @override
  Future<TaskModel?> getById(String id) async {
    _call('getById');
    return stored[id];
  }

  @override
  Future<TaskModel> addTask(TaskModel task) async {
    _call('add');
    await _writeGate();
    if (stored.containsKey(task.id)) {
      throw const StorageException();
    }
    stored[task.id] = task;
    return task;
  }

  @override
  Future<TaskModel> updateTask(TaskModel task) async {
    _call('update');
    await _writeGate();
    final current = stored[task.id];
    if (current == null) {
      throw const StorageException();
    }
    final updated = task.copyWith(
      createdAt: current.createdAt,
      updatedAt: _clock,
    );
    stored[task.id] = updated;
    return updated;
  }

  @override
  Future<void> deleteTask(String id) async {
    _call('delete');
    await _writeGate();
    stored.remove(id);
  }

  @override
  Future<TaskModel> restoreTask(TaskModel task) async {
    _call('restore');
    await _writeGate();
    if (stored.containsKey(task.id)) {
      throw const StorageException();
    }
    stored[task.id] = task;
    return task;
  }

  @override
  Future<TaskModel> toggleDone(String id) async {
    _call('toggle');
    await _writeGate();
    final current = stored[id];
    if (current == null) {
      throw const StorageException();
    }
    final updated = current.copyWith(
      isDone: !current.isDone,
      updatedAt: _clock,
    );
    stored[id] = updated;
    return updated;
  }

  @override
  Future<void> clearAll() async => stored.clear();
}

TaskState _success(List<TaskModel> tasks, {TaskModel? deleted}) =>
    TaskState(status: TaskStatus.success, tasks: tasks, lastDeleted: deleted);

void main() {
  late _FakeTaskRepository repository;
  setUp(() => repository = _FakeTaskRepository([_first, _second]));

  test(
    'constructor does not load and starts with empty initial state',
    () async {
      final cubit = TaskCubit(repository);
      expect(cubit.state, TaskState());
      expect(repository.calls, isEmpty);
      await cubit.close();
    },
  );

  blocTest<TaskCubit, TaskState>(
    'load emits loading then the repository tasks',
    build: () => TaskCubit(repository),
    act: (cubit) => cubit.load(),
    expect: () => [
      TaskState(status: TaskStatus.loading),
      _success([_first, _second]),
    ],
  );

  for (final (error, message) in [
    (const StorageException(), AppStrings.storageError),
    (StateError('Private test-secret failure'), AppStrings.unknownError),
  ]) {
    blocTest<TaskCubit, TaskState>(
      'load maps ${error.runtimeType} to a friendly failure',
      setUp: () => repository.failures['load'] = error,
      build: () => TaskCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        TaskState(status: TaskStatus.loading),
        TaskState(status: TaskStatus.failure, errorMessage: message),
      ],
    );
  }

  final edited = _first.copyWith(
    title: 'Updated report',
    priority: TaskPriority.low,
  );
  final original = _success([_first, _second]);
  final operations =
      <(String, Future<void> Function(TaskCubit), List<TaskModel>, TaskModel?)>[
        ('add', (cubit) => cubit.add(_new), [_new, _first, _second], null),
        (
          'update',
          (cubit) => cubit.update(edited),
          [edited.copyWith(updatedAt: _clock), _second],
          null,
        ),
        (
          'toggle',
          (cubit) => cubit.toggleDone(_first.id),
          [_first.copyWith(isDone: true, updatedAt: _clock), _second],
          null,
        ),
        ('delete', (cubit) => cubit.delete(_first.id), [_second], _first),
      ];
  for (final (operation, action, tasks, deleted) in operations) {
    blocTest<TaskCubit, TaskState>(
      '$operation emits loading then refreshed tasks',
      build: () => TaskCubit(repository),
      seed: () => original,
      act: action,
      expect: () => [
        original.copyWith(status: TaskStatus.loading),
        _success(tasks, deleted: deleted),
      ],
      verify: (_) => expect(repository.calls[operation], 1),
    );
    blocTest<TaskCubit, TaskState>(
      '$operation failure retains the current task snapshot',
      setUp: () => repository.failures[operation] = const StorageException(),
      build: () => TaskCubit(repository),
      seed: () => original,
      act: action,
      expect: () => [
        original.copyWith(status: TaskStatus.loading),
        original.copyWith(
          status: TaskStatus.failure,
          errorMessage: AppStrings.storageError,
        ),
      ],
    );
  }

  blocTest<TaskCubit, TaskState>(
    'undo restores the exact deleted snapshot and clears undo',
    setUp: () => repository = _FakeTaskRepository([_second]),
    build: () => TaskCubit(repository),
    seed: () => _success([_second], deleted: _first),
    act: (cubit) => cubit.undoDelete(),
    expect: () => [
      _success([_second], deleted: _first).copyWith(status: TaskStatus.loading),
      _success([_first, _second]),
    ],
    verify: (_) => expect(repository.stored[_first.id], _first),
  );

  blocTest<TaskCubit, TaskState>(
    'undo failure retains the snapshot for retry',
    setUp: () {
      repository = _FakeTaskRepository([_second]);
      repository.failures['restore'] = const StorageException();
    },
    build: () => TaskCubit(repository),
    seed: () => _success([_second], deleted: _first),
    act: (cubit) => cubit.undoDelete(),
    expect: () => [
      _success([_second], deleted: _first).copyWith(status: TaskStatus.loading),
      _success([_second], deleted: _first).copyWith(
        status: TaskStatus.failure,
        errorMessage: AppStrings.storageError,
      ),
    ],
    verify: (_) => expect(repository.stored.containsKey(_first.id), isFalse),
  );

  blocTest<TaskCubit, TaskState>(
    'undo without a deleted task makes no repository request',
    build: () => TaskCubit(repository),
    act: (cubit) => cubit.undoDelete(),
    expect: () => <TaskState>[],
    verify: (_) => expect(repository.calls, isEmpty),
  );

  blocTest<TaskCubit, TaskState>(
    'committed delete keeps its undo snapshot when refresh fails',
    setUp: () => repository.failures['load'] = const StorageException(),
    build: () => TaskCubit(repository),
    seed: () => original,
    act: (cubit) => cubit.delete(_first.id),
    expect: () => [
      original.copyWith(status: TaskStatus.loading),
      original.copyWith(
        status: TaskStatus.failure,
        errorMessage: AppStrings.storageError,
        lastDeleted: _first,
      ),
    ],
    verify: (_) => expect(repository.stored.containsKey(_first.id), isFalse),
  );

  blocTest<TaskCubit, TaskState>(
    'committed restore clears undo even when refresh fails',
    setUp: () {
      repository = _FakeTaskRepository([_second]);
      repository.failures['load'] = const StorageException();
    },
    build: () => TaskCubit(repository),
    seed: () => _success([_second], deleted: _first),
    act: (cubit) => cubit.undoDelete(),
    expect: () => [
      _success([_second], deleted: _first).copyWith(status: TaskStatus.loading),
      _success([_second]).copyWith(
        status: TaskStatus.failure,
        errorMessage: AppStrings.storageError,
      ),
    ],
    verify: (_) => expect(repository.stored[_first.id], _first),
  );

  test(
    'search matches title and description with combined filters synchronously',
    () async {
      repository = _FakeTaskRepository([_first, _second, _third]);
      final cubit = TaskCubit(repository);
      addTearDown(cubit.close);
      await cubit.load();
      cubit.setQuery('REPORT');
      expect(cubit.state.visibleTasks, [_first]);
      cubit.setQuery('  nOtEs  ');
      expect(cubit.state.visibleTasks, [_first, _second]);
      cubit.setPriorityFilter(TaskPriority.high);
      cubit.setStatusFilter(TaskStatusFilter.pending);
      expect(cubit.state.visibleTasks, [_first]);
      cubit.setStatusFilter(TaskStatusFilter.done);
      expect(cubit.state.visibleTasks, isEmpty);
      cubit.setPriorityFilter(null);
      expect(cubit.state.visibleTasks, [_second]);
      cubit.clearFilters();
      expect(cubit.state.query, '');
      expect(cubit.state.statusFilter, TaskStatusFilter.all);
      expect(cubit.state.priorityFilter, isNull);
      expect(cubit.state.visibleTasks, [_first, _second, _third]);
      expect(repository.calls['load'], 1);
    },
  );

  test('state snapshots and visible collections are immutable copies', () {
    final input = [_first, _second];
    final state = TaskState(tasks: input, query: 'notes');
    input.add(_third);
    expect(state.tasks, [_first, _second]);
    expect(() => state.tasks.add(_third), throwsUnsupportedError);
    expect(() => state.visibleTasks.add(_third), throwsUnsupportedError);
    final copy = state.copyWith(query: 'chapter');
    expect(state.visibleTasks, [_first, _second]);
    expect(copy.visibleTasks, [_second]);
  });

  test('state equality includes all fields and explicit clear flags win', () {
    final state = original.copyWith(
      query: 'notes',
      statusFilter: TaskStatusFilter.pending,
      priorityFilter: TaskPriority.high,
      errorMessage: 'An error',
      lastDeleted: _third,
    );
    expect(state.copyWith(), state);
    for (final changed in [
      state.copyWith(status: TaskStatus.failure),
      state.copyWith(tasks: [_first]),
      state.copyWith(query: 'other'),
      state.copyWith(statusFilter: TaskStatusFilter.done),
      state.copyWith(priorityFilter: TaskPriority.low),
      state.copyWith(errorMessage: 'Another error'),
      state.copyWith(lastDeleted: _first),
    ]) {
      expect(changed, isNot(state));
    }
    final cleared = state.copyWith(
      priorityFilter: TaskPriority.low,
      clearPriorityFilter: true,
      errorMessage: 'Ignored',
      clearError: true,
      lastDeleted: _first,
      clearLastDeleted: true,
    );
    expect(cleared.priorityFilter, isNull);
    expect(cleared.errorMessage, isNull);
    expect(cleared.lastDeleted, isNull);
  });

  test(
    'filters changed during a pending load survive its completion',
    () async {
      final pending = Completer<List<TaskModel>>();
      repository.nextLoad = pending;
      final cubit = TaskCubit(repository);
      addTearDown(cubit.close);
      final request = cubit.load();
      cubit.setQuery('notes');
      cubit.setStatusFilter(TaskStatusFilter.done);
      cubit.setPriorityFilter(TaskPriority.low);
      pending.complete([_first, _second]);
      await request;
      expect(cubit.state.status, TaskStatus.success);
      expect(cubit.state.query, 'notes');
      expect(cubit.state.statusFilter, TaskStatusFilter.done);
      expect(cubit.state.priorityFilter, TaskPriority.low);
      expect(cubit.state.visibleTasks, [_second]);
    },
  );

  test('filters changed during a pending write survive refresh', () async {
    final cubit = TaskCubit(repository);
    addTearDown(cubit.close);
    await cubit.load();
    cubit.setQuery('notes');
    cubit.setPriorityFilter(TaskPriority.high);
    final pending = Completer<void>();
    repository.nextWrite = pending;
    final request = cubit.add(_new);
    cubit.setQuery('NEW');
    cubit.setStatusFilter(TaskStatusFilter.pending);
    cubit.setPriorityFilter(TaskPriority.low);
    pending.complete();
    await request;
    expect(cubit.state.status, TaskStatus.success);
    expect(cubit.state.query, 'NEW');
    expect(cubit.state.statusFilter, TaskStatusFilter.pending);
    expect(cubit.state.priorityFilter, TaskPriority.low);
    expect(cubit.state.visibleTasks, [_new]);
  });

  test('a pending load blocks duplicate and competing mutations', () async {
    final pending = Completer<List<TaskModel>>();
    repository.nextLoad = pending;
    final cubit = TaskCubit(repository);
    addTearDown(cubit.close);
    final request = cubit.load();
    await cubit.load();
    await cubit.add(_new);
    await cubit.update(_first);
    await cubit.delete(_first.id);
    await cubit.toggleDone(_first.id);
    expect(repository.calls, {'load': 1});
    pending.complete([_first, _second]);
    await request;
    expect(cubit.state, original);
  });

  blocTest<TaskCubit, TaskState>(
    'reset clears tasks, errors, filters and undo',
    build: () => TaskCubit(repository),
    seed: () => original.copyWith(
      status: TaskStatus.failure,
      query: 'notes',
      statusFilter: TaskStatusFilter.done,
      priorityFilter: TaskPriority.low,
      errorMessage: AppStrings.storageError,
      lastDeleted: _third,
    ),
    act: (cubit) => cubit.reset(),
    expect: () => [TaskState()],
  );

  for (final fail in [false, true]) {
    test(
      'reset rejects stale ${fail ? 'failure' : 'success'} without releasing a newer load',
      () async {
        final oldPending = Completer<List<TaskModel>>();
        final newPending = Completer<List<TaskModel>>();
        repository.nextLoad = oldPending;
        final cubit = TaskCubit(repository);
        addTearDown(cubit.close);
        final oldRequest = cubit.load();
        cubit.reset();
        expect(cubit.state, TaskState());
        repository.nextLoad = newPending;
        final newRequest = cubit.load();
        if (fail) {
          oldPending.completeError(const StorageException());
        } else {
          oldPending.complete([_first]);
        }
        await oldRequest;
        expect(cubit.state.status, TaskStatus.loading);
        expect(cubit.state.tasks, isEmpty);
        await cubit.add(_new);
        expect(repository.calls['add'], isNull);
        expect(repository.calls['load'], 2);
        newPending.complete([_third]);
        await newRequest;
        expect(cubit.state, _success([_third]));
      },
    );

    test(
      'close suppresses pending ${fail ? 'failure' : 'success'} emissions',
      () async {
        final pending = Completer<List<TaskModel>>();
        repository.nextLoad = pending;
        final cubit = TaskCubit(repository);
        final states = <TaskState>[];
        final subscription = cubit.stream.listen(states.add);
        final request = cubit.load();
        await cubit.close();
        if (fail) {
          pending.completeError(const StorageException());
        } else {
          pending.complete([_first, _second]);
        }
        await expectLater(request, completes);
        expect(states, [TaskState(status: TaskStatus.loading)]);
        cubit.reset();
        cubit.setQuery('after close');
        await cubit.load();
        expect(repository.calls['load'], 1);
        expect(cubit.state.status, TaskStatus.loading);
        await subscription.cancel();
      },
    );
  }
}
