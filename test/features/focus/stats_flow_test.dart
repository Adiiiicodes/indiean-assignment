import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryHive extends HiveService {
  final boxes = <String, Map<String, String>>{};
  @override
  List<String> readAll(String box) => boxes[box]?.values.toList() ?? [];
  @override
  String? read(String box, String key) => boxes[box]?[key];
  @override
  Future<void> put(String box, String key, String value) async {
    (boxes[box] ??= {})[key] = value;
  }

  @override
  Future<void> delete(String box, String key) async => boxes[box]?.remove(key);
  @override
  Future<void> clear(String box) async => boxes[box]?.clear();
}

class _CountingFocus extends FocusRepository {
  _CountingFocus(HiveService hive, TaskRepository tasks)
    : super(FocusLocalDatasource(hive), tasks);
  int reads = 0;
  @override
  Future<FocusStats> todayStats() {
    reads++;
    return super.todayStats();
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets(
    'real app refreshes task stats, tab snapshots and confirmed clear',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        AppConstants.sessionUserKey: 'demo-user',
      });
      final prefs = await SharedPreferences.getInstance();
      final hive = _MemoryHive();
      final tasks = TaskRepository(TaskLocalDatasource(hive));
      final focus = _CountingFocus(hive, tasks);
      final now = DateTime.now();
      final task = TaskModel(
        title: 'Review focus stats',
        createdAt: now,
        updatedAt: now,
      );
      await tasks.addTask(task);
      Future<void> save(String id) async {
        await focus.addSession(
          FocusSessionModel(
            id: id,
            taskId: task.id,
            taskTitle: task.title,
            plannedMinutes: 25,
            actualSeconds: 61,
            startedAt: now,
            endedAt: now.add(const Duration(seconds: 61)),
            completed: false,
          ),
        );
      }

      await save('first');
      final dependencies = AppDependencies(
        prefs: PrefsService(prefs),
        hive: hive,
        tasks: tasks,
        focus: focus,
      );
      addTearDown(() => dependencies.dio.close(force: true));
      await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
      await tester.pump(AppConstants.splashDuration);
      await _frames(tester);
      final context = tester.element(find.byType(TasksTab));
      final stats = context.read<StatsCubit>();
      final taskCubit = context.read<TaskCubit>();
      expect(
        stats.state.stats,
        const FocusStats(
          sessionsToday: 1,
          focusMinutesToday: 1,
          currentStreakDays: 1,
        ),
      );
      await taskCubit.toggleDone(task.id);
      await _frames(tester);
      expect(stats.state.stats.tasksCompletedToday, 1);
      final readCount = focus.reads;
      taskCubit.setQuery('review');
      taskCubit.setStatusFilter(TaskStatusFilter.done);
      await _frames(tester);
      expect(
        focus.reads,
        readCount,
        reason: 'Filters do not change stored stats',
      );
      await taskCubit.delete(task.id);
      await _frames(tester);
      expect(stats.state.stats.tasksCompletedToday, 0);
      await taskCubit.undoDelete();
      await _frames(tester);
      expect(stats.state.stats.tasksCompletedToday, 1);
      await save('second');
      await tester.tap(_tab(AppStrings.profile));
      await _frames(tester);
      expect(
        stats.state.stats,
        const FocusStats(
          sessionsToday: 2,
          focusMinutesToday: 2,
          tasksCompletedToday: 1,
          currentStreakDays: 1,
        ),
      );
      expect(find.byType(ProfileScreen), findsOneWidget);
      final clear = find.byKey(const ValueKey('profile-clear-data'));
      await tester.ensureVisible(clear);
      await _frames(tester);
      await tester.tap(clear);
      await _frames(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(AppStrings.clearData),
        ),
      );
      await _frames(tester);
      expect(stats.state.stats, const FocusStats());
      expect(await focus.getSessions(), isEmpty);
      expect(await tasks.getTasks(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
  );
}
