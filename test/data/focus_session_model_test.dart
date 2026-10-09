import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/focus_stats.dart';

void main() {
  final start = DateTime.utc(2026, 10, 10, 8);
  final session = FocusSessionModel(
    id: 'session-1',
    taskId: 'task-1',
    taskTitle: 'Read a chapter',
    plannedMinutes: 25,
    actualSeconds: 1500,
    completed: true,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 25)),
  );

  test('JSON preserves every field and UTC timestamps', () {
    final json = session.toJson();
    expect(json, {
      'id': 'session-1',
      'taskId': 'task-1',
      'taskTitle': 'Read a chapter',
      'plannedMinutes': 25,
      'actualSeconds': 1500,
      'completed': true,
      'startedAt': start.toIso8601String(),
      'endedAt': start.add(const Duration(minutes: 25)).toIso8601String(),
    });
    expect(FocusSessionModel.fromJson(json), session);
    json['taskTitle'] = 'Changed copy';
    expect(session.taskTitle, 'Read a chapter');
  });

  test(
    'missing constructor ID generates unique UUIDs without changing fields',
    () {
      FocusSessionModel create() => FocusSessionModel(
        taskId: session.taskId,
        taskTitle: session.taskTitle,
        plannedMinutes: 15,
        actualSeconds: 0,
        completed: false,
        startedAt: start,
        endedAt: start,
      );
      final first = create();
      final second = create();
      expect(
        first.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(second.id, isNot(first.id));
      expect(first.actualSeconds, 0);
      expect(FocusSessionModel.fromJson(first.toJson()), first);
    },
  );

  final invalidValues = <String, Object?>{
    'id': ' ',
    'taskId': 1,
    'taskTitle': '',
    'plannedMinutes': 25.0,
    'actualSeconds': -1,
    'completed': 'true',
    'startedAt': 'not-a-date',
    'endedAt': '2026-10-10T07:59:59Z',
  };
  for (final entry in invalidValues.entries) {
    test('rejects missing and invalid ${entry.key}', () {
      final missing = session.toJson()..remove(entry.key);
      final invalid = session.toJson()..[entry.key] = entry.value;
      expect(() => FocusSessionModel.fromJson(missing), throwsFormatException);
      expect(() => FocusSessionModel.fromJson(invalid), throwsFormatException);
    });
  }

  test(
    'rejects nonpositive plans, floating seconds and normalized bad dates',
    () {
      for (final value in [0, -1]) {
        expect(
          () => session.copyWith(plannedMinutes: value),
          throwsFormatException,
        );
      }
      expect(() => session.copyWith(id: ''), throwsFormatException);
      expect(
        () => FocusSessionModel.fromJson(
          session.toJson()..['actualSeconds'] = 1.5,
        ),
        throwsFormatException,
      );
      for (final value in [
        '2026-02-30T08:00:00Z',
        '2026-10-10T24:00:00Z',
        '2026-10-10T08:60:00Z',
      ]) {
        expect(
          () => FocusSessionModel.fromJson(
            session.toJson()..['startedAt'] = value,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('copyWith can replace all fields and retains immutable original', () {
    final updated = session.copyWith(
      id: 'session-2',
      taskId: 'task-2',
      taskTitle: 'Draft a page',
      plannedMinutes: 45,
      actualSeconds: 125,
      completed: false,
      startedAt: start.add(const Duration(days: 1)),
      endedAt: start.add(const Duration(days: 1, seconds: 125)),
    );
    expect(updated.toJson(), {
      'id': 'session-2',
      'taskId': 'task-2',
      'taskTitle': 'Draft a page',
      'plannedMinutes': 45,
      'actualSeconds': 125,
      'completed': false,
      'startedAt': start.add(const Duration(days: 1)).toIso8601String(),
      'endedAt': start
          .add(const Duration(days: 1, seconds: 125))
          .toIso8601String(),
    });
    expect(session.actualSeconds, 1500);
    expect(session.copyWith(), session);
    for (final changed in [
      session.copyWith(id: 'other'),
      session.copyWith(taskId: 'other'),
      session.copyWith(taskTitle: 'Other title'),
      session.copyWith(plannedMinutes: 45),
      session.copyWith(actualSeconds: 120),
      session.copyWith(completed: false),
      session.copyWith(startedAt: start.subtract(const Duration(seconds: 1))),
      session.copyWith(
        endedAt: session.endedAt.add(const Duration(seconds: 1)),
      ),
    ]) {
      expect(changed, isNot(session));
    }
  });

  test('stats equality includes each metric and defaults are zero', () {
    expect(
      const FocusStats(),
      const FocusStats(
        sessionsToday: 0,
        focusMinutesToday: 0,
        tasksCompletedToday: 0,
        currentStreakDays: 0,
      ),
    );
    for (final changed in [
      const FocusStats(sessionsToday: 1),
      const FocusStats(focusMinutesToday: 1),
      const FocusStats(tasksCompletedToday: 1),
      const FocusStats(currentStreakDays: 1),
    ]) {
      expect(changed, isNot(const FocusStats()));
    }
  });
}
