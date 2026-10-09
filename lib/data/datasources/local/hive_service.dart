import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveService {
  HiveService({HiveInterface? hive}) : _hive = hive ?? Hive;

  final HiveInterface _hive;

  Future<void> init({String? path}) async {
    try {
      if (path != null) {
        _hive.init(path);
      } else {
        await _hive.initFlutter();
      }
      await _hive.openBox<String>(AppConstants.tasksBox);
      await _hive.openBox<String>(AppConstants.focusSessionsBox);
    } catch (_) {
      throw const StorageException();
    }
  }

  List<String> readAll(String boxName) {
    try {
      return _box(boxName).values.toList(growable: false);
    } catch (_) {
      throw const StorageException();
    }
  }

  String? read(String boxName, String key) {
    try {
      return _box(boxName).get(key);
    } catch (_) {
      throw const StorageException();
    }
  }

  Future<void> put(String boxName, String key, String json) async {
    try {
      await _box(boxName).put(key, json);
    } catch (_) {
      throw const StorageException();
    }
  }

  Future<void> delete(String boxName, String key) async {
    try {
      await _box(boxName).delete(key);
    } catch (_) {
      throw const StorageException();
    }
  }

  Future<void> clear(String boxName) async {
    try {
      await _box(boxName).clear();
    } catch (_) {
      throw const StorageException();
    }
  }

  Future<void> close() async {
    try {
      await _hive.close();
    } catch (_) {
      throw const StorageException();
    }
  }

  Box<String> _box(String boxName) {
    if ((boxName != AppConstants.tasksBox &&
            boxName != AppConstants.focusSessionsBox) ||
        !_hive.isBoxOpen(boxName)) {
      throw const StorageException();
    }
    return _hive.box<String>(boxName);
  }
}
