import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _GatedHive extends HiveService {
  _GatedHive() : super(hive: Hive);
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  final tasksCleared = Completer<void>();

  @override
  Future<void> put(String boxName, String key, String json) async {
    if (boxName == AppConstants.focusSessionsBox && !writeStarted.isCompleted) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    await super.put(boxName, key, json);
  }

  @override
  Future<void> clear(String boxName) async {
    await super.clear(boxName);
    if (boxName == AppConstants.tasksBox && !tasksCleared.isCompleted) {
      tasksCleared.complete();
    }
  }
}

FocusSessionModel _session(DateTime day, {String id = 'focus-1'}) =>
    FocusSessionModel(
      id: id,
      taskId: 'shared-task',
      taskTitle: 'Shared task title',
      plannedMinutes: 25,
      actualSeconds: 120,
      completed: false,
      startedAt: DateTime(day.year, day.month, day.day, 12),
      endedAt: DateTime(day.year, day.month, day.day, 12, 2),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HiveService hive;
  late PrefsService prefs;
  late SharedPreferences preferences;

  setUp(() async {
    await Hive.close();
    directory = await Directory.systemTemp.createTemp(
      'focusdesk_focus_dependencies_',
    );
    hive = HiveService(hive: Hive);
    await hive.init(path: directory.path);
    SharedPreferences.setMockInitialValues({
      AppConstants.sessionUserKey: 'demo-user',
      AppConstants.themeModeKey: 'dark',
      AppConstants.focusDurationKey: 45,
    });
    preferences = await SharedPreferences.getInstance();
    prefs = PrefsService(preferences);
  });

  tearDown(() async {
    await Hive.close();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    expect(target.startsWith('$tempRoot${Platform.pathSeparator}'), isTrue);
    await directory.delete(recursive: true);
  });

  AppDependencies dependencies({
    HiveService? storage,
    FocusRepository? focus,
    TaskRepository? tasks,
  }) {
    final result = AppDependencies(
      prefs: prefs,
      hive: storage ?? hive,
      focus: focus,
      tasks: tasks,
    );
    addTearDown(() => result.dio.close(force: true));
    return result;
  }

  test('default Focus repository reads shared task changes and persists sessions across reopen', () async {
    final app = dependencies();
    final now = DateTime.now();
    await app.tasks.addTask(
      TaskModel(id: 'shared-task', title: 'Shared task title'),
    );
    await app.tasks.addTask(
      TaskModel(
        id: 'done-today',
        title: 'Already done',
        isDone: true,
        updatedAt: now,
      ),
    );
    await app.tasks.addTask(
      TaskModel(
        id: 'done-before',
        title: 'Done yesterday',
        isDone: true,
        updatedAt: DateTime(now.year, now.month, now.day - 1, 12),
      ),
    );
    final session = _session(now);
    expect(await app.focus.addSession(session), session);
    expect(
      jsonDecode(hive.read(AppConstants.focusSessionsBox, session.id)!),
      session.toJson(),
    );
    expect(await app.focus.sessionsForDay(now), [session]);
    expect(
      await app.focus.todayStats(),
      const FocusStats(
        sessionsToday: 1,
        focusMinutesToday: 2,
        tasksCompletedToday: 1,
        currentStreakDays: 1,
      ),
    );
    await app.tasks.toggleDone('shared-task');
    expect((await app.focus.todayStats()).tasksCompletedToday, 2);

    await hive.close();
    hive = HiveService(hive: Hive);
    await hive.init(path: directory.path);
    final reopened = dependencies();
    expect(await reopened.focus.getSessions(), [session]);
    expect((await reopened.focus.todayStats()).tasksCompletedToday, 2);
  });

  testWidgets(
    'injected Focus repository is the exact app-scoped provider from the first frame',
    (tester) async {
      final tasks = TaskRepository(TaskLocalDatasource(hive));
      final focus = FocusRepository(FocusLocalDatasource(hive), tasks);
      final app = dependencies(focus: focus, tasks: tasks);
      expect(app.focus, same(focus));
      await tester.pumpWidget(FocusDeskApp(dependencies: app));
      final splash = find.byType(SplashScreen);
      expect(splash, findsOneWidget);
      expect(tester.element(splash).read<FocusRepository>(), same(focus));
      expect(tester.element(splash).read<TaskRepository>(), same(tasks));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  test('default Profile clear empties shared tasks and focus but retains account and preferences', () async {
    final app = dependencies();
    final user = await app.auth.currentUser();
    expect(user, isNotNull);
    final accounts = preferences.getString(AppConstants.usersKey);
    await app.tasks.addTask(
      TaskModel(id: 'shared-task', title: 'Shared task title'),
    );
    await app.focus.addSession(_session(DateTime.now()));
    await app.profile.clearAllData();
    expect(await app.tasks.getTasks(), isEmpty);
    expect(await app.focus.getSessions(), isEmpty);
    expect(hive.readAll(AppConstants.tasksBox), isEmpty);
    expect(hive.readAll(AppConstants.focusSessionsBox), isEmpty);
    expect(await app.focus.todayStats(), const FocusStats());
    expect(await app.auth.currentUser(), user);
    expect(preferences.getString(AppConstants.usersKey), accounts);
    expect(preferences.getString(AppConstants.sessionUserKey), user!.id);
    expect(preferences.getString(AppConstants.themeModeKey), 'dark');
    expect(preferences.getInt(AppConstants.focusDurationKey), 45);
  });

  test('Profile clear queues behind a pending Focus write so the session cannot return afterward', () async {
    final gated = _GatedHive();
    final app = dependencies(storage: gated);
    final adding = app.focus.addSession(_session(DateTime.now()));
    await gated.writeStarted.future;
    var cleared = false;
    final clearing = app.profile.clearAllData().then((_) => cleared = true);
    await gated.tasksCleared.future;
    await Future<void>.delayed(Duration.zero);
    expect(cleared, isFalse);
    expect(hive.readAll(AppConstants.focusSessionsBox), isEmpty);
    gated.releaseWrite.complete();
    await adding;
    await clearing;
    expect(cleared, isTrue);
    expect(await app.focus.getSessions(), isEmpty);
    expect(hive.readAll(AppConstants.focusSessionsBox), isEmpty);
    expect(preferences.getString(AppConstants.sessionUserKey), 'demo-user');
  });
}
