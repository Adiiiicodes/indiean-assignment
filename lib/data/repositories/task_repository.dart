import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';

class TaskRepository {
  TaskRepository(TaskLocalDatasource datasource, {DateTime Function()? now})
    : _datasource = datasource,
      _now = now ?? DateTime.now;

  final TaskLocalDatasource _datasource;
  final DateTime Function() _now;
  Future<void> _writeQueue = Future<void>.value();

  Future<List<TaskModel>> getTasks() => _guard(() async {
    final tasks = [...await _datasource.getTasks()];
    tasks.sort((a, b) {
      final createdOrder = b.createdAt.compareTo(a.createdAt);
      return createdOrder != 0 ? createdOrder : a.id.compareTo(b.id);
    });
    return tasks;
  });

  Future<TaskModel?> getById(String id) =>
      _guard(() => _datasource.getById(id));

  Future<TaskModel> addTask(TaskModel task) => _mutate(() => _insert(task));

  Future<TaskModel> updateTask(TaskModel task) => _mutate(() async {
    final current = await _requiredTask(task.id);
    final updated = task.copyWith(
      id: current.id,
      createdAt: current.createdAt,
      updatedAt: _now(),
    );
    await _datasource.put(updated);
    return updated;
  });

  Future<void> deleteTask(String id) => _mutate(() async {
    // Validate any existing record before deleting so corrupt data is not
    // silently removed by a failed read or an inconsistent stored identity.
    final current = await _datasource.getById(id);
    if (current != null) await _datasource.delete(id);
  });

  Future<TaskModel> restoreTask(TaskModel task) => _mutate(() => _insert(task));

  Future<TaskModel> toggleDone(String id) => _mutate(() async {
    final current = await _requiredTask(id);
    final updated = current.copyWith(
      isDone: !current.isDone,
      updatedAt: _now(),
    );
    await _datasource.put(updated);
    return updated;
  });

  Future<void> clearAll() => _mutate(_datasource.clear);

  Future<TaskModel> _insert(TaskModel task) async {
    if (await _datasource.getById(task.id) != null) {
      throw const StorageException();
    }
    await _datasource.put(task);
    return task;
  }

  Future<TaskModel> _requiredTask(String id) async {
    final task = await _datasource.getById(id);
    if (task == null) throw const StorageException();
    return task;
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    // Serialize read/modify/write operations, including duplicate-id checks.
    final result = _writeQueue.then((_) => _guard(operation));
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (_) {
      throw const StorageException();
    }
  }
}
