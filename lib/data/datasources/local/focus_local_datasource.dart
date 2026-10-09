import 'dart:async';
import 'dart:convert';

import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';

class FocusLocalDatasource {
  FocusLocalDatasource(this._hive);
  final HiveService _hive;

  Future<List<FocusSessionModel>> getSessions() => _guard(() {
    final records = _hive.readAll(AppConstants.focusSessionsBox);
    final sessions = records.map(_decode).toList();
    final ids = <String>{};
    for (var index = 0; index < sessions.length; index++) {
      final id = sessions[index].id;
      if (!ids.add(id) ||
          _hive.read(AppConstants.focusSessionsBox, id) != records[index]) {
        throw const StorageException();
      }
    }
    return sessions;
  });

  Future<FocusSessionModel?> getById(String id) => _guard(() {
    final record = _hive.read(AppConstants.focusSessionsBox, id);
    if (record == null) return null;
    final session = _decode(record);
    if (session.id != id) throw const StorageException();
    return session;
  });

  Future<void> put(FocusSessionModel session) => _guard(
    () => _hive.put(
      AppConstants.focusSessionsBox,
      session.id,
      jsonEncode(session.toJson()),
    ),
  );

  Future<void> clear() =>
      _guard(() => _hive.clear(AppConstants.focusSessionsBox));

  FocusSessionModel _decode(String record) {
    final json = jsonDecode(record);
    if (json is! Map<String, dynamic>) throw const StorageException();
    return FocusSessionModel.fromJson(json);
  }

  Future<T> _guard<T>(FutureOr<T> Function() operation) async {
    try {
      return await operation();
    } catch (_) {
      throw const StorageException();
    }
  }
}
