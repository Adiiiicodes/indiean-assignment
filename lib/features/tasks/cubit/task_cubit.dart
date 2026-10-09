import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';

class TaskCubit extends Cubit<TaskState> {
  TaskCubit(TaskRepository repository)
    : _repository = repository,
      super(TaskState());

  final TaskRepository _repository;
  bool _busy = false;
  int _generation = 0;

  Future<void> load() => _run();

  Future<void> add(TaskModel task) => _change(() => _repository.addTask(task));

  Future<void> update(TaskModel task) =>
      _change(() => _repository.updateTask(task));

  Future<void> toggleDone(String id) =>
      _change(() => _repository.toggleDone(id));

  Future<void> delete(String id) => _run((generation) async {
    final task = await _repository.getById(id);
    if (!_active(generation)) return const _UndoChange();
    if (task == null) throw const StorageException();
    await _repository.deleteTask(id);
    return _UndoChange(deleted: task);
  });

  Future<void> undoDelete() {
    final deleted = state.lastDeleted;
    if (deleted == null) return Future<void>.value();
    return _run((generation) async {
      if (!_active(generation)) return const _UndoChange();
      await _repository.restoreTask(deleted);
      return const _UndoChange(clear: true);
    });
  }

  void setQuery(String query) {
    if (!isClosed) emit(state.copyWith(query: query));
  }

  void setStatusFilter(TaskStatusFilter filter) {
    if (!isClosed) emit(state.copyWith(statusFilter: filter));
  }

  void setPriorityFilter(TaskPriority? filter) {
    if (!isClosed) {
      emit(
        state.copyWith(
          priorityFilter: filter,
          clearPriorityFilter: filter == null,
        ),
      );
    }
  }

  void clearFilters() {
    if (!isClosed) {
      emit(
        state.copyWith(
          query: '',
          statusFilter: TaskStatusFilter.all,
          clearPriorityFilter: true,
        ),
      );
    }
  }

  void reset() {
    if (isClosed) return;
    _generation++;
    _busy = false;
    emit(TaskState());
  }

  Future<void> _change(Future<TaskModel> Function() mutation) {
    return _run((generation) async {
      if (!_active(generation)) return const _UndoChange();
      await mutation();
      return const _UndoChange();
    });
  }

  Future<void> _run([
    Future<_UndoChange> Function(int generation)? mutation,
  ]) async {
    if (isClosed || _busy) return;
    final generation = _generation;
    _busy = true;
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    _UndoChange? undoChange;
    try {
      if (mutation != null) undoChange = await mutation(generation);
      if (!_active(generation)) return;
      final tasks = await _repository.getTasks();
      if (!_active(generation)) return;
      emit(
        state.copyWith(
          status: TaskStatus.success,
          tasks: tasks,
          clearError: true,
          lastDeleted: undoChange?.deleted,
          clearLastDeleted: undoChange?.clear ?? false,
        ),
      );
    } catch (error) {
      if (_active(generation)) {
        emit(
          state.copyWith(
            status: TaskStatus.failure,
            errorMessage: mapException(error).message,
            lastDeleted: undoChange?.deleted,
            clearLastDeleted: undoChange?.clear ?? false,
          ),
        );
      }
    } finally {
      if (_generation == generation) _busy = false;
    }
  }

  bool _active(int generation) => !isClosed && _generation == generation;
}

class _UndoChange {
  const _UndoChange({this.deleted, this.clear = false});

  final TaskModel? deleted;
  final bool clear;
}
