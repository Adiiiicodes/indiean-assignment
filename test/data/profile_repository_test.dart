import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/profile_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AuthRepository extends Mock implements AuthRepository {}

class _TaskRepository extends Mock implements TaskRepository {}

class _HiveService extends Mock implements HiveService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = UserModel(
    id: 'user-1',
    name: 'Demo User',
    email: 'demo@focusdesk.app',
    createdAt: DateTime.utc(2026, 10, 1),
  );

  group('delegation and failure handling', () {
    late _AuthRepository auth;
    late _TaskRepository tasks;
    late _HiveService hive;
    late ProfileRepository repository;

    setUp(() {
      auth = _AuthRepository();
      tasks = _TaskRepository();
      hive = _HiveService();
      repository = ProfileRepository(auth, tasks, hive);
      when(() => tasks.clearAll()).thenAnswer((_) async {});
      when(() => hive.clear(AppConstants.focusSessionsBox))
          .thenAnswer((_) async {});
    });

    test('name update returns the shared auth repository identity', () async {
      final updated = user.copyWith(name: 'Updated Name');
      when(() => auth.updateName('Updated Name'))
          .thenAnswer((_) async => updated);
      expect(await repository.updateName('Updated Name'), same(updated));
      verify(() => auth.updateName('Updated Name')).called(1);
      verifyNever(() => tasks.clearAll());
      verifyNever(() => hive.clear(any()));
    });

    test(
      'name validation remains friendly and does not become storage failure',
      () async {
        when(() => auth.updateName('x'))
            .thenThrow(const ValidationException(AppStrings.nameInvalid));
        await expectLater(
          repository.updateName('x'),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              AppStrings.nameInvalid,
            ),
          ),
        );
      },
    );

    test('focus clear waits until queued task clearing completes', () async {
      final gate = Completer<void>();
      when(() => tasks.clearAll()).thenAnswer((_) => gate.future);
      final pending = repository.clearAllData();
      await Future<void>.delayed(Duration.zero);
      verify(() => tasks.clearAll()).called(1);
      verifyNever(() => hive.clear(any()));
      gate.complete();
      await pending;
      verify(() => hive.clear(AppConstants.focusSessionsBox)).called(1);
      verifyNever(() => hive.clear(AppConstants.tasksBox));
      verifyNever(() => auth.logout());
    });

    test('task clear failure stops before modifying focus records', () async {
      when(() => tasks.clearAll()).thenThrow(const StorageException());
      await expectLater(
        repository.clearAllData(),
        throwsA(isA<StorageException>()),
      );
      verifyNever(() => hive.clear(any()));
    });

    test('unknown backend details are mapped to a friendly failure', () async {
      when(() => hive.clear(AppConstants.focusSessionsBox))
          .thenThrow(StateError('private-file-path-secret'));
      await expectLater(
        repository.clearAllData(),
        throwsA(
          isA<UnknownException>()
              .having((e) => e.message, 'message', AppStrings.unknownError)
              .having(
                (e) => e.toString(),
                'private details',
                isNot(contains('private-file')),
              ),
        ),
      );
    });
  });

  group('real persisted profile data', () {
    late Directory directory;
    late HiveService hive;
    late SharedPreferences preferences;
    late AuthRepository auth;
    late TaskRepository tasks;
    late ProfileRepository repository;

    setUp(() async {
      await Hive.close();
      directory = await Directory.systemTemp.createTemp('focusdesk_profile_');
      hive = HiveService(hive: Hive);
      await hive.init(path: directory.path);
      SharedPreferences.setMockInitialValues({
        AppConstants.themeModeKey: 'dark',
        AppConstants.focusDurationKey: 45,
      });
      preferences = await SharedPreferences.getInstance();
      auth = AuthRepository(
        AuthLocalDatasource(PrefsService(preferences)),
        delay: Duration.zero,
      );
      await auth.login(
        email: AppConstants.demoEmail,
        password: AppConstants.demoPassword,
      );
      tasks = TaskRepository(TaskLocalDatasource(hive));
      repository = ProfileRepository(auth, tasks, hive);
    });

    tearDown(() async {
      await Hive.close();
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final target = await directory.resolveSymbolicLinks();
      expect(target.startsWith('$tempRoot${Platform.pathSeparator}'), isTrue);
      await directory.delete(recursive: true);
    });

    test('rename persists identity, credentials and current session', () async {
      final original = (await auth.currentUser())!;
      final before =
          jsonDecode(preferences.getString(AppConstants.usersKey)!) as List;
      final passwordHash = (before.single as Map)['passwordHash'];
      final updated = await repository.updateName('  Focus Person  ');
      expect(updated.name, 'Focus Person');
      expect(updated.id, original.id);
      expect(updated.email, original.email);
      expect(updated.createdAt, original.createdAt);
      expect(await auth.currentUser(), updated);
      final after =
          jsonDecode(preferences.getString(AppConstants.usersKey)!) as List;
      expect((after.single as Map)['passwordHash'], passwordHash);
      expect(preferences.getString(AppConstants.sessionUserKey), original.id);
    });

    test(
      'clear removes both boxes but preserves account/session and preferences',
      () async {
        await tasks.addTask(
          TaskModel(id: 'task-1', title: 'Plan a focus session'),
        );
        await tasks.addTask(
          TaskModel(id: 'task-2', title: 'Review the draft', isDone: true),
        );
        await hive.put(
          AppConstants.focusSessionsBox,
          'session-1',
          '{"id":"session-1"}',
        );
        final accounts = preferences.getString(AppConstants.usersKey);
        final session = preferences.getString(AppConstants.sessionUserKey);
        final current = await auth.currentUser();

        await repository.clearAllData();

        expect(await tasks.getTasks(), isEmpty);
        expect(hive.readAll(AppConstants.focusSessionsBox), isEmpty);
        expect(preferences.getString(AppConstants.usersKey), accounts);
        expect(preferences.getString(AppConstants.sessionUserKey), session);
        expect(preferences.getString(AppConstants.themeModeKey), 'dark');
        expect(preferences.getInt(AppConstants.focusDurationKey), 45);
        expect(await auth.currentUser(), current);
        await hive.close();
        await hive.init(path: directory.path);
        expect(hive.readAll(AppConstants.tasksBox), isEmpty);
        expect(hive.readAll(AppConstants.focusSessionsBox), isEmpty);
      },
    );
  });
}
