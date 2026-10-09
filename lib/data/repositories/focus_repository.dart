import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';

class FocusRepository {
  FocusRepository(this._datasource, this._tasks, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final FocusLocalDatasource _datasource;
  final TaskRepository _tasks;
  final DateTime Function() _now;
  Future<void> _writes = Future<void>.value();

  Future<FocusSessionModel> addSession(FocusSessionModel session) =>
      _mutate(() async {
        final existing = await _datasource.getById(session.id);
        if (existing != null) {
          if (existing == session) return existing;
          throw const StorageException();
        }
        await _datasource.put(session);
        return session;
      });

  Future<List<FocusSessionModel>> getSessions() => _guard(() async {
    await _writes;
    final sessions = [...await _datasource.getSessions()];
    sessions.sort((a, b) {
      final newest = b.startedAt.compareTo(a.startedAt);
      return newest != 0 ? newest : a.id.compareTo(b.id);
    });
    return List.unmodifiable(sessions);
  });

  Future<List<FocusSessionModel>> sessionsForDay(DateTime day) =>
      _guard(() async {
        final calendarDay = _day(day);
        return List.unmodifiable(
          (await getSessions()).where(
            (session) => _day(session.startedAt) == calendarDay,
          ),
        );
      });

  Future<FocusStats> todayStats() => _guard(() async {
    final today = _day(_now());
    final sessions = await getSessions();
    final todays = sessions.where(
      (session) => _day(session.startedAt) == today,
    );
    final seconds = todays.fold<int>(
      0,
      (sum, session) => sum + session.actualSeconds,
    );
    final tasks = await _tasks.getTasks();
    final activeDays = sessions
        .where((session) => session.actualSeconds > 0)
        .map((session) => _day(session.startedAt))
        .toSet();
    var cursor = activeDays.contains(today) ? today : _previousDay(today);
    var streak = 0;
    while (activeDays.contains(cursor)) {
      streak++;
      cursor = _previousDay(cursor);
    }
    return FocusStats(
      sessionsToday: todays.length,
      focusMinutesToday: seconds ~/ 60,
      tasksCompletedToday: tasks
          .where((task) => task.isDone && _day(task.updatedAt) == today)
          .length,
      currentStreakDays: streak,
    );
  });

  Future<void> clearAll() => _mutate(_datasource.clear);

  static DateTime _day(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  // Calendar construction preserves adjacent local dates over DST changes.
  static DateTime _previousDay(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _writes.then((_) => _guard(operation));
    _writes = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
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
