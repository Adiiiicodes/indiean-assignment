import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';
import 'package:focusdesk/data/models/suggested_page_model.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';

SuggestedTaskModel _item(int id) => SuggestedTaskModel(
  id: id,
  todo: 'Suggested task $id',
  completed: id.isEven,
  userId: 7,
);
SuggestedPageModel _page({int skip = 0, int total = 22}) {
  final count = total - skip < 20 ? total - skip : 20;
  return SuggestedPageModel(
    todos: [
      for (var index = 0; index < count; index++) _item(skip + index + 1),
    ],
    total: total,
    skip: skip,
    limit: count,
  );
}

class _Remote extends SuggestedRemoteDatasource {
  _Remote() : super(Dio());
}

class _Repository extends SuggestedRepository {
  _Repository() : super(_Remote());
  final requests = <(int, int)>[];
  Future<SuggestedPageModel> Function(int limit, int skip)? reply;

  @override
  Future<SuggestedPageModel> fetch({int limit = 20, int skip = 0}) {
    requests.add((limit, skip));
    return reply?.call(limit, skip) ?? Future.value(_page(skip: skip));
  }
}

class _Local extends TaskLocalDatasource {
  _Local() : super(HiveService());
  final saved = <String, TaskModel>{};
  int writes = 0;
  bool failWrites = false;
  bool failReads = false;
  bool failReadAfterWrite = false;
  Completer<void>? pendingWrite;

  @override
  Future<List<TaskModel>> getTasks() async {
    if (failReads) throw const StorageException();
    return saved.values.toList();
  }

  @override
  Future<TaskModel?> getById(String id) async => saved[id];
  @override
  Future<void> put(TaskModel task) async {
    writes++;
    await pendingWrite?.future;
    if (failWrites) throw const StorageException();
    saved[task.id] = task;
    if (failReadAfterWrite) failReads = true;
  }

  @override
  Future<void> delete(String id) async {
    saved.remove(id);
  }

  @override
  Future<void> clear() async => saved.clear();
}

TypeMatcher<SuggestedState> _status(SuggestedStatus status) =>
    isA<SuggestedState>().having((state) => state.status, 'status', status);
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Repository repository;
  late _Local local;
  late TaskRepository taskRepository;
  late TaskCubit tasks;

  setUp(() {
    repository = _Repository();
    local = _Local();
    taskRepository = TaskRepository(local);
    tasks = TaskCubit(taskRepository);
  });
  tearDown(() async {
    await tasks.close();
  });

  SuggestedCubit create() => SuggestedCubit(repository, tasks);

  test('state copies collections and retains value identity', () {
    final items = [_item(1)];
    final imported = {1};
    final importing = {2};
    final state = SuggestedState(
      status: SuggestedStatus.success,
      items: items,
      importedIds: imported,
      importingIds: importing,
    );
    items.clear();
    imported.clear();
    importing.clear();
    expect(state.items, [_item(1)]);
    expect(state.importedIds, {1});
    expect(state.importingIds, {2});
    expect(() => state.items.clear(), throwsUnsupportedError);
    expect(() => state.importedIds.clear(), throwsUnsupportedError);
    expect(() => state.importingIds.clear(), throwsUnsupportedError);
    expect(state.copyWith(), state);
    expect(
      state
          .copyWith(errorMessage: 'Friendly')
          .copyWith(clearError: true)
          .errorMessage,
      isNull,
    );
  });

  blocTest<SuggestedCubit, SuggestedState>(
    'first load emits loading then first page',
    build: create,
    act: (cubit) => cubit.load(),
    expect: () => [
      _status(SuggestedStatus.loading),
      _status(SuggestedStatus.success)
          .having((state) => state.items.length, 'items', 20)
          .having((state) => state.hasMore, 'hasMore', true),
    ],
    verify: (_) => expect(repository.requests, [(20, 0)]),
  );

  blocTest<SuggestedCubit, SuggestedState>(
    'initial network failure remains friendly and retry loads',
    build: () {
      repository.reply = (_, _) async => throw const NetworkException();
      return create();
    },
    act: (cubit) async {
      await cubit.load();
      repository.reply = null;
      await cubit.load();
    },
    expect: () => [
      _status(SuggestedStatus.loading),
      _status(SuggestedStatus.failure).having(
        (state) => state.errorMessage,
        'message',
        AppStrings.networkError,
      ),
      _status(SuggestedStatus.loading),
      _status(SuggestedStatus.success),
    ],
  );

  test(
    'clamped final page appends and repeated loadMore stops at the end',
    () async {
      final cubit = create();
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.loadMore();
      await cubit.loadMore();
      expect(repository.requests, [(20, 0), (20, 20)]);
      expect(cubit.state.items.map((item) => item.id), [
        for (var id = 1; id <= 22; id++) id,
      ]);
      expect(cubit.state.hasMore, isFalse);
      expect(cubit.state.isLoadingMore, isFalse);
    },
  );

  test(
    'refresh retains visible rows while pending and replaces the page',
    () async {
      final cubit = create();
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.loadMore();
      final pending = Completer<SuggestedPageModel>();
      repository.reply = (_, _) => pending.future;
      final refresh = cubit.refresh();
      expect(cubit.state.status, SuggestedStatus.loading);
      expect(cubit.state.items, hasLength(22));
      pending.complete(_page(total: 3));
      await refresh;
      expect(cubit.state.items, [_item(1), _item(2), _item(3)]);
      expect(cubit.state.hasMore, isFalse);
      expect(repository.requests.last, (20, 0));
    },
  );

  test('loadMore failure retains rows and retries the same offset', () async {
    final cubit = create();
    addTearDown(cubit.close);
    await cubit.load();
    repository.reply = (_, _) async => throw const TimeoutAppException();
    await cubit.loadMore();
    expect(cubit.state.status, SuggestedStatus.failure);
    expect(cubit.state.items, hasLength(20));
    expect(cubit.state.hasMore, isTrue);
    expect(cubit.state.isLoadingMore, isFalse);
    expect(cubit.state.errorMessage, AppStrings.timeoutError);
    repository.reply = null;
    await cubit.loadMore();
    expect(repository.requests, [(20, 0), (20, 20), (20, 20)]);
    expect(cubit.state.items, hasLength(22));
    expect(cubit.state.errorMessage, isNull);
  });

  test('refresh failure keeps existing items and succeeds on retry', () async {
    final cubit = create();
    addTearDown(cubit.close);
    await cubit.load();
    repository.reply = (_, _) async => throw StateError('test-secret');
    await cubit.refresh();
    expect(cubit.state.status, SuggestedStatus.failure);
    expect(cubit.state.items, hasLength(20));
    expect(cubit.state.errorMessage, AppStrings.unknownError);
    repository.reply = null;
    await cubit.refresh();
    expect(cubit.state.status, SuggestedStatus.success);
    expect(cubit.state.errorMessage, isNull);
  });

  test(
    'overlapping requests are ignored without launching extra fetches',
    () async {
      final pending = Completer<SuggestedPageModel>();
      repository.reply = (_, _) => pending.future;
      final cubit = create();
      addTearDown(cubit.close);
      final load = cubit.load();
      await cubit.load();
      await cubit.refresh();
      await cubit.loadMore();
      expect(repository.requests, [(20, 0)]);
      pending.complete(_page());
      await load;
      final tail = Completer<SuggestedPageModel>();
      repository.reply = (_, _) => tail.future;
      final more = cubit.loadMore();
      expect(cubit.state.isLoadingMore, isTrue);
      expect(cubit.state.items, hasLength(20));
      await cubit.loadMore();
      expect(repository.requests, [(20, 0), (20, 20)]);
      tail.complete(_page(skip: 20));
      await more;
    },
  );

  test(
    'overlapping page identities are deduplicated without stalling the offset',
    () async {
      repository.reply = (_, skip) async => skip == 0
          ? _page(total: 40)
          : SuggestedPageModel(
              todos: [for (var id = 11; id <= 30; id++) _item(id)],
              total: 40,
              skip: 20,
              limit: 20,
            );
      final cubit = create();
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.loadMore();
      expect(cubit.state.items.map((item) => item.id), [
        for (var id = 1; id <= 30; id++) id,
      ]);
      expect(cubit.state.hasMore, isFalse);
      expect(repository.requests, [(20, 0), (20, 20)]);
    },
  );

  test(
    'invalid page offset fails without appending or advancing the next request',
    () async {
      final cubit = create();
      addTearDown(cubit.close);
      await cubit.load();
      repository.reply = (_, _) async => _page();
      await cubit.loadMore();
      expect(cubit.state.status, SuggestedStatus.failure);
      expect(cubit.state.items, hasLength(20));
      expect(cubit.state.errorMessage, AppStrings.invalidResponse);
      repository.reply = null;
      await cubit.loadMore();
      expect(repository.requests.last, (20, 20));
      expect(cubit.state.items, hasLength(22));
    },
  );

  test(
    'zero-progress malformed response stays retryable with no data loss',
    () async {
      final cubit = create();
      addTearDown(cubit.close);
      await cubit.load();
      repository.reply = (_, _) async =>
          SuggestedPageModel(todos: const [], total: 22, skip: 20, limit: 0);
      await cubit.loadMore();
      expect(cubit.state.status, SuggestedStatus.failure);
      expect(cubit.state.errorMessage, AppStrings.invalidResponse);
      expect(cubit.state.items, hasLength(20));
      repository.reply = null;
      await cubit.loadMore();
      expect(cubit.state.items, hasLength(22));
    },
  );

  test('page repeating only existing identities fails without consuming its offset', () async {
    repository.reply = (_, skip) async => skip == 0
        ? _page(total: 40)
        : SuggestedPageModel(
            todos: [for (var id = 1; id <= 20; id++) _item(id)],
            total: 40,
            skip: 20,
            limit: 20,
          );
    final cubit = create();
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.loadMore();
    expect(cubit.state.status, SuggestedStatus.failure);
    expect(cubit.state.errorMessage, AppStrings.invalidResponse);
    expect(cubit.state.items, hasLength(20));
    repository.reply = (_, skip) async => _page(skip: skip, total: 40);
    await cubit.loadMore();
    expect(repository.requests.last, (20, 20));
    expect(cubit.state.items, hasLength(40));
    expect(cubit.state.hasMore, isFalse);
  });

  test(
    'reset ignores stale completion and preserves a newer operation guard',
    () async {
      final old = Completer<SuggestedPageModel>();
      repository.reply = (_, _) => old.future;
      final cubit = create();
      addTearDown(cubit.close);
      final oldLoad = cubit.load();
      cubit.reset();
      expect(cubit.state.status, SuggestedStatus.initial);
      expect(cubit.state.items, isEmpty);
      final fresh = Completer<SuggestedPageModel>();
      repository.reply = (_, _) => fresh.future;
      final freshLoad = cubit.load();
      old.complete(_page(total: 2));
      await oldLoad;
      expect(cubit.state.status, SuggestedStatus.loading);
      await cubit.load();
      expect(repository.requests, hasLength(2));
      fresh.complete(_page(total: 3));
      await freshLoad;
      expect(cubit.state.items, [_item(1), _item(2), _item(3)]);
    },
  );

  test('close safely ignores pending fetch and future operations', () async {
    final pending = Completer<SuggestedPageModel>();
    repository.reply = (_, _) => pending.future;
    final cubit = create();
    final load = cubit.load();
    await cubit.close();
    pending.complete(_page());
    await load;
    await cubit.load();
    await cubit.refresh();
    await cubit.loadMore();
    cubit.reset();
    expect(await cubit.importTask(_item(1)), isFalse);
    expect(repository.requests, hasLength(1));
    expect(local.writes, 0);
  });

  test(
    'import writes a stable task through the real TaskCubit and marks Added',
    () async {
      final cubit = create();
      addTearDown(cubit.close);
      expect(await cubit.importTask(_item(2)), isTrue);
      await _flush();
      final saved = (await taskRepository.getById('suggested-2'))!;
      expect(saved.title, 'Suggested task 2');
      expect(saved.source, TaskSource.imported);
      expect(saved.priority, TaskPriority.medium);
      expect(saved.isDone, isTrue);
      expect(cubit.state.importedIds, {2});
      expect(cubit.state.importingIds, isEmpty);
      expect(local.writes, 1);
      expect(await cubit.importTask(_item(2)), isTrue);
      expect(local.writes, 1);
    },
  );

  test(
    'persisted imported identity is tracked without overwriting local edits',
    () async {
      final saved = _item(1).toTask().copyWith(title: 'Locally edited title');
      local.saved[saved.id] = saved;
      await tasks.load();
      final cubit = create();
      addTearDown(cubit.close);
      expect(cubit.state.importedIds, {1});
      expect(await cubit.importTask(_item(1)), isTrue);
      expect(local.writes, 0);
      expect(await taskRepository.getById(saved.id), saved);
    },
  );

  test(
    'local identity collision never overwrites a task or reports Added',
    () async {
      final existing = TaskModel(
        id: 'suggested-1',
        title: 'Existing local task',
      );
      local.saved[existing.id] = existing;
      await tasks.load();
      final cubit = create();
      addTearDown(cubit.close);
      expect(await cubit.importTask(_item(1)), isFalse);
      expect(cubit.state.importedIds, isEmpty);
      expect(cubit.state.errorMessage, AppStrings.storageError);
      expect(local.writes, 0);
      expect(await taskRepository.getById(existing.id), existing);
    },
  );

  test('failed import is not marked Added and remains retryable', () async {
    local.failWrites = true;
    final cubit = create();
    addTearDown(cubit.close);
    expect(await cubit.importTask(_item(1)), isFalse);
    expect(cubit.state.importedIds, isEmpty);
    expect(cubit.state.importingIds, isEmpty);
    expect(cubit.state.errorMessage, AppStrings.storageError);
    local.failWrites = false;
    expect(await cubit.importTask(_item(1)), isTrue);
    await _flush();
    expect(cubit.state.importedIds, {1});
    expect(local.writes, 2);
    expect(local.saved, hasLength(1));
  });

  test('retry reconciles committed import after a failed read without duplicate write', () async {
    local.failReadAfterWrite = true;
    final cubit = create();
    addTearDown(cubit.close);
    expect(await cubit.importTask(_item(1)), isFalse);
    expect(local.saved.keys, ['suggested-1']);
    expect(cubit.state.importedIds, isEmpty);
    local.failReadAfterWrite = false;
    local.failReads = false;
    expect(await cubit.importTask(_item(1)), isTrue);
    await _flush();
    expect(local.writes, 1);
    expect(cubit.state.importedIds, {1});
    expect(cubit.state.errorMessage, isNull);
  });

  test(
    'task delete, Undo and clear update Added from shared persisted state',
    () async {
      final cubit = create();
      addTearDown(cubit.close);
      await cubit.importTask(_item(1));
      await _flush();
      await tasks.delete('suggested-1');
      await _flush();
      expect(cubit.state.importedIds, isEmpty);
      await tasks.undoDelete();
      await _flush();
      expect(cubit.state.importedIds, {1});
      await taskRepository.clearAll();
      await tasks.load();
      await _flush();
      expect(cubit.state.importedIds, isEmpty);
    },
  );

  test(
    'same-ID overlapping import is skipped and one exact task is stored',
    () async {
      await tasks.load();
      final pending = Completer<void>();
      local.pendingWrite = pending;
      final cubit = create();
      addTearDown(cubit.close);
      final first = cubit.importTask(_item(1));
      await _flush();
      expect(cubit.state.importingIds, {1});
      expect(await cubit.importTask(_item(1)), isFalse);
      expect(local.writes, 1);
      pending.complete();
      expect(await first, isTrue);
      await _flush();
      expect(local.saved, hasLength(1));
      expect(cubit.state.importingIds, isEmpty);
    },
  );

  test(
    'import waits for another task write before adding its own identity',
    () async {
      await tasks.load();
      final pending = Completer<void>();
      local.pendingWrite = pending;
      final other = tasks.add(
        TaskModel(id: 'local-task', title: 'Another local task'),
      );
      await _flush();
      final cubit = create();
      addTearDown(cubit.close);
      final importing = cubit.importTask(_item(1));
      await _flush();
      expect(local.writes, 1);
      pending.complete();
      await other;
      expect(await importing, isTrue);
      await _flush();
      expect(local.saved.keys.toSet(), {'local-task', 'suggested-1'});
      expect(cubit.state.importedIds, {1});
      expect(tasks.state.status, TaskStatus.success);
    },
  );

  test(
    'different imported identities queue without losing either task write',
    () async {
      await tasks.load();
      final pending = Completer<void>();
      local.pendingWrite = pending;
      final cubit = create();
      addTearDown(cubit.close);
      final first = cubit.importTask(_item(1));
      await _flush();
      final second = cubit.importTask(_item(2));
      await _flush();
      expect(local.writes, 1);
      expect(cubit.state.importingIds, {1, 2});
      pending.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      await _flush();
      expect(local.writes, 2);
      expect(local.saved.keys.toSet(), {'suggested-1', 'suggested-2'});
      expect(cubit.state.importedIds, {1, 2});
      expect(cubit.state.importingIds, isEmpty);
    },
  );

  test('close during an import ignores its later UI result safely', () async {
    await tasks.load();
    final pending = Completer<void>();
    local.pendingWrite = pending;
    final cubit = create();
    final importing = cubit.importTask(_item(1));
    await _flush();
    expect(local.writes, 1);
    await cubit.close();
    pending.complete();
    expect(await importing, isFalse);
    expect(cubit.isClosed, isTrue);
    expect(local.saved.keys, ['suggested-1']);
  });
}
