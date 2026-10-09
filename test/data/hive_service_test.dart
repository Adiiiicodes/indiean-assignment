import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

class _MockHive extends Mock implements HiveInterface {}

class _MockBox extends Mock implements Box<String> {}

Matcher get _storageFailure => isA<StorageException>().having(
  (error) => error.message,
  'friendly message',
  AppStrings.storageError,
);

void main() {
  group('HiveService on disk', () {
    late Directory directory;
    late HiveService service;

    setUp(() async {
      await Hive.close();
      directory = await Directory.systemTemp.createTemp('focusdesk_hive_test_');
      service = HiveService(hive: Hive);
      await service.init(path: directory.path);
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('opens both string boxes and reads an empty or missing value', () {
      expect(Hive.isBoxOpen(AppConstants.tasksBox), isTrue);
      expect(Hive.isBoxOpen(AppConstants.focusSessionsBox), isTrue);
      expect(service.readAll(AppConstants.tasksBox), isEmpty);
      expect(service.read(AppConstants.tasksBox, 'missing'), isNull);
    });

    test('round trips JSON strings separately in both boxes', () async {
      const task = '{"id":"task-1","title":"Read a chapter"}';
      const session = '{"id":"session-1","minutes":25}';
      await service.put(AppConstants.tasksBox, 'task-1', task);
      await service.put(AppConstants.focusSessionsBox, 'session-1', session);

      expect(service.read(AppConstants.tasksBox, 'task-1'), task);
      expect(service.readAll(AppConstants.tasksBox), [task]);
      expect(service.readAll(AppConstants.focusSessionsBox), [session]);
      expect(service.read(AppConstants.focusSessionsBox, 'task-1'), isNull);
    });

    test('persists values across close and reopen', () async {
      const json = '{"id":"persisted","title":"Keep this task"}';
      await service.put(AppConstants.tasksBox, 'persisted', json);
      await service.close();
      expect(
        () => service.readAll(AppConstants.tasksBox),
        throwsA(_storageFailure),
      );

      service = HiveService(hive: Hive);
      await service.init(path: directory.path);
      expect(service.read(AppConstants.tasksBox, 'persisted'), json);
    });

    test(
      'updates an existing key and deletes only the requested entry',
      () async {
        await service.put(AppConstants.tasksBox, 'first', '{"title":"Old"}');
        await service.put(AppConstants.tasksBox, 'second', '{"title":"Keep"}');
        await service.put(AppConstants.tasksBox, 'first', '{"title":"New"}');
        expect(service.read(AppConstants.tasksBox, 'first'), '{"title":"New"}');
        expect(service.readAll(AppConstants.tasksBox), hasLength(2));

        await service.delete(AppConstants.tasksBox, 'first');
        await service.delete(AppConstants.tasksBox, 'missing');
        expect(service.read(AppConstants.tasksBox, 'first'), isNull);
        expect(service.readAll(AppConstants.tasksBox), ['{"title":"Keep"}']);
      },
    );

    test('clears one box without touching the other box', () async {
      await service.put(AppConstants.tasksBox, 'task', '{"title":"Task"}');
      await service.put(
        AppConstants.focusSessionsBox,
        'session',
        '{"minutes":15}',
      );
      await service.clear(AppConstants.tasksBox);

      expect(service.readAll(AppConstants.tasksBox), isEmpty);
      expect(service.readAll(AppConstants.focusSessionsBox), [
        '{"minutes":15}',
      ]);
      await service.clear(AppConstants.focusSessionsBox);
      expect(service.readAll(AppConstants.focusSessionsBox), isEmpty);
    });

    test('rejects unknown box names with a friendly storage failure', () async {
      expect(() => service.readAll('unknown'), throwsA(_storageFailure));
      expect(() => service.read('unknown', 'key'), throwsA(_storageFailure));
      await expectLater(
        service.put('unknown', 'key', '{}'),
        throwsA(_storageFailure),
      );
      await expectLater(
        service.delete('unknown', 'key'),
        throwsA(_storageFailure),
      );
      await expectLater(service.clear('unknown'), throwsA(_storageFailure));
    });
  });

  group('HiveService failure mapping', () {
    late _MockHive hive;
    late _MockBox box;
    late HiveService service;

    setUp(() {
      hive = _MockHive();
      box = _MockBox();
      service = HiveService(hive: hive);
      when(() => hive.isBoxOpen(AppConstants.tasksBox)).thenReturn(true);
      when(() => hive.box<String>(AppConstants.tasksBox)).thenReturn(box);
    });

    test('maps initialization errors', () async {
      when(() => hive.init(any())).thenThrow(StateError('private disk error'));
      await expectLater(service.init(path: '/test'), throwsA(_storageFailure));
    });

    test('maps box opening errors', () async {
      when(() => hive.openBox<String>(AppConstants.tasksBox))
          .thenAnswer((_) async => throw StateError('private open error'));
      await expectLater(service.init(path: '/test'), throwsA(_storageFailure));
    });

    test('maps readAll errors', () {
      when(() => box.values).thenThrow(StateError('private read error'));
      expect(
        () => service.readAll(AppConstants.tasksBox),
        throwsA(_storageFailure),
      );
    });

    test('maps read errors', () {
      when(() => box.get('key')).thenThrow(StateError('private read error'));
      expect(
        () => service.read(AppConstants.tasksBox, 'key'),
        throwsA(_storageFailure),
      );
    });

    test('maps write errors', () async {
      when(() => box.put('key', '{}'))
          .thenAnswer((_) async => throw StateError('private write error'));
      await expectLater(
        service.put(AppConstants.tasksBox, 'key', '{}'),
        throwsA(_storageFailure),
      );
    });

    test('maps deletion errors', () async {
      when(() => box.delete('key'))
          .thenAnswer((_) async => throw StateError('private delete error'));
      await expectLater(
        service.delete(AppConstants.tasksBox, 'key'),
        throwsA(_storageFailure),
      );
    });

    test('maps clear errors', () async {
      when(() => box.clear())
          .thenAnswer((_) async => throw StateError('private clear error'));
      await expectLater(
        service.clear(AppConstants.tasksBox),
        throwsA(_storageFailure),
      );
    });

    test('maps close errors', () async {
      when(() => hive.close())
          .thenAnswer((_) async => throw StateError('private close error'));
      await expectLater(service.close(), throwsA(_storageFailure));
    });

    test('maps box lookup errors', () {
      when(() => hive.box<String>(AppConstants.tasksBox))
          .thenThrow(StateError('private box error'));
      expect(
        () => service.readAll(AppConstants.tasksBox),
        throwsA(_storageFailure),
      );
    });
  });
}
