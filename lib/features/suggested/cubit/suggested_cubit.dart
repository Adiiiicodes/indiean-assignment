import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';

class SuggestedCubit extends Cubit<SuggestedState> {
  SuggestedCubit(this._repository, this._tasks)
    : super(SuggestedState(importedIds: _importedIds(_tasks.state))) {
    _taskSubscription = _tasks.stream.listen(_syncImports);
  }

  final SuggestedRepository _repository;
  final TaskCubit _tasks;
  late final StreamSubscription<TaskState> _taskSubscription;
  Future<void> _importTail = Future<void>.value();
  bool _pageBusy = false;
  bool _closing = false;
  int _generation = 0;
  int _nextSkip = 0;

  Future<void> load() => _fetchFirst();
  Future<void> refresh() => _fetchFirst();
  Future<void> loadMore() => _fetch(more: true);
  Future<void> _fetchFirst() => _fetch(more: false);

  Future<void> _fetch({required bool more}) async {
    if (isClosed || _closing || _pageBusy || (more && !state.hasMore)) return;
    final generation = _generation;
    final skip = more ? _nextSkip : 0;
    _pageBusy = true;
    emit(
      state.copyWith(
        status: more ? SuggestedStatus.success : SuggestedStatus.loading,
        isLoadingMore: more,
        clearError: true,
      ),
    );
    try {
      final page = await _repository.fetch(
        limit: AppConstants.pageSize,
        skip: skip,
      );
      if (!_active(generation)) return;
      final nextSkip = page.skip + page.todos.length;
      if (page.skip != skip || (nextSkip <= skip && skip < page.total)) {
        throw const FormatException('Suggested pagination made no progress.');
      }
      final previousIds = more
          ? state.items.map((task) => task.id).toSet()
          : <int>{};
      final added = page.todos
          .where((task) => !previousIds.contains(task.id))
          .toList();
      if (more && page.todos.isNotEmpty && added.isEmpty) {
        throw const FormatException('Suggested page repeated existing items.');
      }
      _nextSkip = nextSkip;
      emit(
        state.copyWith(
          status: SuggestedStatus.success,
          items: [...(more ? state.items : <SuggestedTaskModel>[]), ...added],
          hasMore: nextSkip < page.total,
          isLoadingMore: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_active(generation)) {
        emit(
          state.copyWith(
            status: SuggestedStatus.failure,
            isLoadingMore: false,
            errorMessage: mapException(error).message,
          ),
        );
      }
    } finally {
      if (_generation == generation) _pageBusy = false;
    }
  }

  Future<bool> importTask(SuggestedTaskModel suggested) async {
    if (isClosed || _closing || state.importingIds.contains(suggested.id)) {
      return false;
    }
    final generation = _generation;
    final previous = _importTail;
    final completion = Completer<void>();
    _importTail = completion.future;
    emit(state.copyWith(importingIds: {...state.importingIds, suggested.id}));
    try {
      await previous;
      if (!_active(generation)) return false;
      if (!await _ensureTasksReady(generation)) return false;
      if (!_active(generation)) return false;
      // Another task action may start while the hydration Future completes.
      while (_tasks.state.status != TaskStatus.success) {
        if (!await _ensureTasksReady(generation) || !_active(generation)) {
          return false;
        }
      }
      if (_tasks.isClosed) throw const StorageException();
      final id = 'suggested-${suggested.id}';
      final existing = _findTask(id);
      if (existing != null) {
        if (existing.source != TaskSource.imported) {
          throw const StorageException();
        }
        _importSucceeded();
        return true;
      }
      final task = suggested.toTask();
      await _tasks.add(task);
      if (!_active(generation)) return false;
      final saved = _findTask(id);
      if (_tasks.state.status != TaskStatus.success ||
          saved == null ||
          saved.title != task.title ||
          saved.description != task.description ||
          saved.priority != task.priority ||
          saved.dueDate != task.dueDate ||
          saved.isDone != task.isDone ||
          saved.source != TaskSource.imported) {
        throw StorageException(
          _tasks.state.errorMessage ?? AppStrings.storageError,
        );
      }
      _importSucceeded();
      return true;
    } catch (error) {
      if (_active(generation)) {
        emit(
          state.copyWith(
            status: SuggestedStatus.failure,
            errorMessage: mapException(error).message,
          ),
        );
      }
      return false;
    } finally {
      if (!completion.isCompleted) completion.complete();
      if (_active(generation)) {
        emit(
          state.copyWith(
            importingIds: {...state.importingIds}..remove(suggested.id),
          ),
        );
      }
    }
  }

  Future<bool> _ensureTasksReady(int generation) async {
    if (_tasks.isClosed) throw const StorageException();
    if (_tasks.state.status == TaskStatus.loading) {
      await _tasks.stream.firstWhere(
        (state) => state.status != TaskStatus.loading,
      );
      if (!_active(generation)) return false;
    }
    if (_tasks.isClosed) throw const StorageException();
    if (_tasks.state.status == TaskStatus.initial ||
        _tasks.state.status == TaskStatus.failure) {
      await _tasks.load();
      if (!_active(generation)) return false;
    }
    if (_tasks.state.status != TaskStatus.success) {
      throw StorageException(
        _tasks.state.errorMessage ?? AppStrings.storageError,
      );
    }
    return true;
  }

  TaskModel? _findTask(String id) {
    for (final task in _tasks.state.tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _importSucceeded() {
    emit(
      state.copyWith(
        status:
            state.status == SuggestedStatus.failure && state.items.isNotEmpty
            ? SuggestedStatus.success
            : state.status,
        importedIds: _importedIds(_tasks.state),
        clearError: true,
      ),
    );
  }

  static Set<int> _importedIds(TaskState state) {
    final ids = <int>{};
    for (final task in state.tasks) {
      if (task.source != TaskSource.imported ||
          !task.id.startsWith('suggested-')) {
        continue;
      }
      final id = int.tryParse(task.id.substring('suggested-'.length));
      if (id != null && id > 0 && task.id == 'suggested-$id') ids.add(id);
    }
    return ids;
  }

  void _syncImports(TaskState tasks) {
    if (!isClosed && !_closing) {
      emit(state.copyWith(importedIds: _importedIds(tasks)));
    }
  }

  void reset() {
    if (isClosed || _closing) return;
    _generation++;
    _pageBusy = false;
    _nextSkip = 0;
    _importTail = Future<void>.value();
    emit(SuggestedState(importedIds: _importedIds(_tasks.state)));
  }

  bool _active(int generation) =>
      !isClosed && !_closing && _generation == generation;

  @override
  Future<void> close() async {
    _closing = true;
    _generation++;
    final cancellation = _taskSubscription.cancel();
    await super.close();
    await cancellation;
  }
}
