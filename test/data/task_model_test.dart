import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/data/models/task_model.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test('impossible calendar dates and times use safe defaults', () {
    final now = DateTime(2026, 10, 9);
    for (final invalid in [
      '2026-02-30T12:00:00',
      '2026-13-01T12:00:00',
      '2026-10-09T25:00:00',
      '2026-10-09T12:61:00',
    ]) {
      final parsed = TaskModel.fromJson({
        'title': 'Recovered date',
        'dueDate': invalid,
        'createdAt': invalid,
        'updatedAt': invalid,
      }, now: now);
      expect(parsed.dueDate, isNull, reason: invalid);
      expect(parsed.createdAt, now, reason: invalid);
      expect(parsed.updatedAt, now, reason: invalid);
    }
    final leap = TaskModel.fromJson({
      'title': 'Leap day',
      'dueDate': '2028-02-29',
    });
    expect(leap.dueDate, DateTime(2028, 2, 29));
  });

  final created = DateTime.utc(2026, 10, 9, 15);
  final updated = DateTime.utc(2026, 10, 9, 15, 45);
  final due = DateTime.utc(2026, 10, 12, 18, 30);
  final task = TaskModel(
    id: '2742c909-1bd8-4cdb-851a-bf5b32cf782b',
    title: 'Write the assignment',
    description: 'Draft the outline.\nReview the examples.',
    priority: TaskPriority.high,
    dueDate: due,
    isDone: true,
    createdAt: created,
    updatedAt: updated,
    source: TaskSource.imported,
  );

  test('every field round-trips through real JSON encoding', () {
    final json = task.toJson();
    expect(json, {
      'id': task.id,
      'title': task.title,
      'description': task.description,
      'priority': 'high',
      'dueDate': due.toIso8601String(),
      'isDone': true,
      'createdAt': created.toIso8601String(),
      'updatedAt': updated.toIso8601String(),
      'source': 'imported',
    });
    final restored = TaskModel.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
    expect(restored, task);
    expect(restored.dueDate!.isUtc, isTrue);
    expect(restored.createdAt.isUtc, isTrue);
    expect(restored.updatedAt.isUtc, isTrue);
  });

  test('missing fields use safe defaults and a fixed fallback date', () {
    final fallback = DateTime(2026, 10, 9, 22, 30);
    final parsed = TaskModel.fromJson({}, now: fallback);
    expect(parsed.id, matches(_uuidV4));
    expect(parsed.title, AppStrings.untitledTask);
    expect(parsed.description, '');
    expect(parsed.priority, TaskPriority.medium);
    expect(parsed.dueDate, isNull);
    expect(parsed.isDone, isFalse);
    expect(parsed.createdAt, fallback);
    expect(parsed.updatedAt, fallback);
    expect(parsed.source, TaskSource.local);
    expect(TaskModel.fromJson(parsed.toJson()), parsed);
  });

  test('invalid field types and dates fall back without throwing', () {
    final fallback = DateTime.utc(2026, 10, 9);
    final parsed = TaskModel.fromJson({
      'id': 12,
      'title': false,
      'description': ['unexpected'],
      'priority': 99,
      'dueDate': 'bad-date',
      'isDone': 'true',
      'createdAt': {},
      'updatedAt': ['bad-date'],
      'source': true,
    }, now: fallback);
    expect(parsed.id, matches(_uuidV4));
    expect(parsed.title, AppStrings.untitledTask);
    expect(parsed.description, '');
    expect(parsed.priority, TaskPriority.medium);
    expect(parsed.dueDate, isNull);
    expect(parsed.isDone, isFalse);
    expect(parsed.createdAt, fallback);
    expect(parsed.updatedAt, fallback);
    expect(parsed.source, TaskSource.local);
  });

  test('blank identity/title and malformed dates use defined fallbacks', () {
    final parsed = TaskModel.fromJson({
      ...task.toJson(),
      'id': '   ',
      'title': '\n ',
      'description': null,
      'dueDate': true,
      'createdAt': 'not-a-date',
      'updatedAt': 'not-a-date',
    }, now: created);
    expect(parsed.id, matches(_uuidV4));
    expect(parsed.title, AppStrings.untitledTask);
    expect(parsed.description, '');
    expect(parsed.dueDate, isNull);
    expect(parsed.createdAt, created);
    expect(parsed.updatedAt, created);
  });

  test('invalid update date falls back to a valid creation date', () {
    final parsed = TaskModel.fromJson({
      ...task.toJson(),
      'updatedAt': 'not-a-date',
    }, now: DateTime(2030));
    expect(parsed.createdAt, created);
    expect(parsed.updatedAt, created);
  });

  test(
    'new tasks generate independent UUIDs and share their captured timestamp',
    () {
      final before = DateTime.now();
      final first = TaskModel(title: 'First task');
      final second = TaskModel(title: 'Second task', id: '');
      final after = DateTime.now();
      expect(first.id, matches(_uuidV4));
      expect(second.id, matches(_uuidV4));
      expect(first.id, isNot(second.id));
      expect(first.createdAt.isBefore(before), isFalse);
      expect(first.createdAt.isAfter(after), isFalse);
      expect(first.updatedAt, first.createdAt);
      expect(first.priority, TaskPriority.medium);
      expect(first.source, TaskSource.local);
      expect(first.isDone, isFalse);
      expect(first.description, '');
      expect(first.dueDate, isNull);
    },
  );

  test(
    'priority labels and parsing accept enum names without case or padding',
    () {
      for (final (priority, label) in [
        (TaskPriority.low, AppStrings.priorityLow),
        (TaskPriority.medium, AppStrings.priorityMedium),
        (TaskPriority.high, AppStrings.priorityHigh),
      ]) {
        expect(priority.label, label);
        expect(TaskPriority.fromValue(priority), priority);
        expect(
          TaskPriority.fromValue(' ${priority.name.toUpperCase()} '),
          priority,
        );
        expect(
          TaskModel.fromJson({...task.toJson(), 'priority': priority.name})
              .priority,
          priority,
        );
      }
      for (final value in [null, '', 'urgent', 12, true, []]) {
        expect(TaskPriority.fromValue(value), TaskPriority.medium);
      }
    },
  );

  test(
    'source parsing preserves valid sources and defaults unknown values',
    () {
      for (final source in TaskSource.values) {
        expect(TaskSource.fromValue(source), source);
        expect(TaskSource.fromValue(' ${source.name.toUpperCase()} '), source);
        expect(
          TaskModel.fromJson({...task.toJson(), 'source': source.name}).source,
          source,
        );
      }
      for (final value in [null, '', 'remote', 12, false, {}]) {
        expect(TaskSource.fromValue(value), TaskSource.local);
      }
    },
  );

  test('copyWith replaces every field without mutating the original', () {
    final snapshot = task.toJson();
    final replacement = task.copyWith(
      id: '72d63ac6-36e5-4b67-94c2-bb54bbfabf4e',
      title: 'Read one chapter',
      description: 'Take notes.',
      priority: TaskPriority.low,
      dueDate: due.add(const Duration(days: 1)),
      isDone: false,
      createdAt: created.add(const Duration(days: 1)),
      updatedAt: updated.add(const Duration(days: 1)),
      source: TaskSource.local,
    );
    expect(replacement.id, '72d63ac6-36e5-4b67-94c2-bb54bbfabf4e');
    expect(replacement.title, 'Read one chapter');
    expect(replacement.description, 'Take notes.');
    expect(replacement.priority, TaskPriority.low);
    expect(replacement.dueDate, due.add(const Duration(days: 1)));
    expect(replacement.isDone, isFalse);
    expect(replacement.createdAt, created.add(const Duration(days: 1)));
    expect(replacement.updatedAt, updated.add(const Duration(days: 1)));
    expect(replacement.source, TaskSource.local);
    expect(task.toJson(), snapshot);
    expect(task.copyWith(), task);
  });

  test('due date is preserved unless explicitly cleared and clear wins', () {
    expect(task.copyWith(title: 'Renamed').dueDate, due);
    final cleared = task.copyWith(clearDueDate: true);
    expect(cleared.dueDate, isNull);
    expect(cleared, task.copyWith(dueDate: due, clearDueDate: true));
    expect(TaskModel.fromJson(cleared.toJson()).dueDate, isNull);
    expect(task.dueDate, due);
  });

  test('equality and hashCode include every task field', () {
    final same = TaskModel.fromJson(task.toJson());
    expect(same, task);
    expect(same.hashCode, task.hashCode);
    final variants = [
      task.copyWith(id: 'another-id'),
      task.copyWith(title: 'Another title'),
      task.copyWith(description: 'Another description'),
      task.copyWith(priority: TaskPriority.low),
      task.copyWith(clearDueDate: true),
      task.copyWith(isDone: false),
      task.copyWith(createdAt: created.add(const Duration(seconds: 1))),
      task.copyWith(updatedAt: updated.add(const Duration(seconds: 1))),
      task.copyWith(source: TaskSource.local),
    ];
    for (final variant in variants) {
      expect(variant, isNot(task));
    }
  });

  test(
    'pending tasks are overdue only before today and due today on this day',
    () {
      final now = DateTime(2026, 10, 12, 12);
      for (final (date, overdue, today) in [
        (DateTime(2026, 10, 11, 23, 59), true, false),
        (DateTime(2026, 10, 12), false, true),
        (DateTime(2026, 10, 12, 23, 59), false, true),
        (DateTime(2026, 10, 13), false, false),
      ]) {
        final pending = task.copyWith(isDone: false, dueDate: date);
        expect(pending.isOverdueAt(now), overdue, reason: date.toString());
        expect(pending.isDueTodayAt(now), today, reason: date.toString());
        expect(pending.copyWith(isDone: true).isOverdueAt(now), isFalse);
        expect(pending.copyWith(isDone: true).isDueTodayAt(now), isFalse);
      }
      final noDate = task.copyWith(isDone: false, clearDueDate: true);
      expect(noDate.isOverdueAt(now), isFalse);
      expect(noDate.isDueTodayAt(now), isFalse);
    },
  );

  test('UTC timestamps compare using their local calendar day', () {
    final now = DateTime(2026, 10, 12, 12).toUtc();
    final todayUtc = DateTime(2026, 10, 12, 0, 5).toUtc();
    final yesterdayUtc = DateTime(2026, 10, 11, 23, 59).toUtc();
    final today = task.copyWith(isDone: false, dueDate: todayUtc);
    expect(today.isDueTodayAt(now), isTrue);
    expect(today.isOverdueAt(now), isFalse);
    expect(
      task.copyWith(isDone: false, dueDate: yesterdayUtc).isOverdueAt(now),
      isTrue,
    );
  });

  test(
    'public getters evaluate pending dates against the current local day',
    () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final pendingToday = task.copyWith(isDone: false, dueDate: today);
      expect(pendingToday.isDueToday, isTrue);
      expect(pendingToday.isOverdue, isFalse);
      expect(
        task.copyWith(isDone: false, dueDate: DateTime(2000)).isOverdue,
        isTrue,
      );
      expect(
        task.copyWith(isDone: false, dueDate: DateTime(3000)).isOverdue,
        isFalse,
      );
      expect(pendingToday.copyWith(isDone: true).isDueToday, isFalse);
    },
  );
}
