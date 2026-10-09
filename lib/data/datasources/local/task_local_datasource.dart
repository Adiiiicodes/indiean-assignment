import 'dart:async';
import 'dart:convert';

import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/models/task_model.dart';

class TaskLocalDatasource {
  TaskLocalDatasource(HiveService hive) : _hive = hive;

  final HiveService _hive;

  Future<List<TaskModel>> getTasks() => _guard(() {
    final records = _hive.readAll(AppConstants.tasksBox);
    final tasks = records.map(_decode).toList();
    for (var index = 0; index < tasks.length; index++) {
      if (_hive.read(AppConstants.tasksBox, tasks[index].id) !=
          records[index]) {
        throw const StorageException();
      }
    }
    if (tasks.map((task) => task.id).toSet().length != tasks.length) {
      throw const StorageException();
    }
    return tasks;
  });

  Future<TaskModel?> getById(String id) => _guard(() {
    final encoded = _hive.read(AppConstants.tasksBox, id);
    if (encoded == null) return null;
    final task = _decode(encoded);
    if (task.id != id) throw const StorageException();
    return task;
  });

  Future<void> put(TaskModel task) => _guard(() async {
    if (task.id.trim().isEmpty) throw const StorageException();
    await _hive.put(AppConstants.tasksBox, task.id, jsonEncode(task.toJson()));
  });

  Future<void> delete(String id) =>
      _guard(() => _hive.delete(AppConstants.tasksBox, id));

  Future<void> clear() => _guard(() => _hive.clear(AppConstants.tasksBox));

  TaskModel _decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) throw const StorageException();
    final id = decoded['id'];
    if (id is! String || id.trim().isEmpty) throw const StorageException();
    return TaskModel.fromJson(decoded);
  }

  Future<T> _guard<T>(FutureOr<T> Function() operation) async {
    try {
      return await operation();
    } catch (_) {
      throw const StorageException();
    }
  }
}
