import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:mocktail/mocktail.dart';

class _AuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _TaskCubit extends Cubit<TaskState> implements TaskCubit {
  _TaskCubit(super.initialState);

  final queries = <String>[];
  final statuses = <TaskStatusFilter>[];
  final priorities = <TaskPriority?>[];
  final deletedIds = <String>[];
  final toggledIds = <String>[];
  int loadCalls = 0;
  int clearCalls = 0;
  int undoCalls = 0;
  Completer<void>? pendingLoad;
  Completer<void>? pendingToggle;
  bool failDelete = false;
  bool failUndo = false;

  void publish(TaskState next) => emit(next);

  @override
  Future<void> load() async {
    loadCalls++;
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    await pendingLoad?.future;
    if (!isClosed) {
      emit(state.copyWith(status: TaskStatus.success, clearError: true));
    }
  }

  @override
  void setQuery(String query) {
    queries.add(query);
    emit(state.copyWith(query: query));
  }

  @override
  void setStatusFilter(TaskStatusFilter filter) {
    statuses.add(filter);
    emit(state.copyWith(statusFilter: filter));
  }

  @override
  void setPriorityFilter(TaskPriority? filter) {
    priorities.add(filter);
    emit(
      state.copyWith(
        priorityFilter: filter,
        clearPriorityFilter: filter == null,
      ),
    );
  }

  @override
  void clearFilters() {
    clearCalls++;
    emit(
      state.copyWith(
        query: '',
        statusFilter: TaskStatusFilter.all,
        clearPriorityFilter: true,
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    final snapshot = state.tasks.singleWhere((task) => task.id == id);
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    await Future<void>.value();
    if (failDelete) {
      emit(
        state.copyWith(
          status: TaskStatus.failure,
          errorMessage: AppStrings.storageError,
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: TaskStatus.success,
          tasks: state.tasks.where((task) => task.id != id).toList(),
          lastDeleted: snapshot,
        ),
      );
    }
  }

  @override
  Future<void> undoDelete() async {
    if (state.status == TaskStatus.loading) return;
    undoCalls++;
    final snapshot = state.lastDeleted;
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    await Future<void>.value();
    if (failUndo) {
      emit(
        state.copyWith(
          status: TaskStatus.failure,
          errorMessage: AppStrings.storageError,
        ),
      );
    } else if (snapshot != null) {
      emit(
        state.copyWith(
          status: TaskStatus.success,
          tasks: [...state.tasks, snapshot],
          clearLastDeleted: true,
        ),
      );
    }
  }

  @override
  Future<void> toggleDone(String id) async {
    if (state.status == TaskStatus.loading) return;
    toggledIds.add(id);
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    await pendingToggle?.future;
    if (isClosed) return;
    emit(
      state.copyWith(
        status: TaskStatus.success,
        tasks: [
          for (final task in state.tasks)
            if (task.id == id) task.copyWith(isDone: !task.isDone) else task,
        ],
      ),
    );
  }

  @override
  Future<void> add(TaskModel task) async =>
      emit(state.copyWith(tasks: [...state.tasks, task]));

  @override
  Future<void> update(TaskModel task) async => emit(
    state.copyWith(
      tasks: [
        for (final item in state.tasks)
          if (item.id == task.id) task else item,
      ],
    ),
  );

  @override
  void reset() => emit(TaskState());
}

final _tasks = [
  TaskModel(
    id: 'write',
    title: 'Write release notes',
    description: 'Explain keyboard behavior',
    priority: TaskPriority.high,
    createdAt: DateTime(2026, 10, 9),
  ),
  TaskModel(
    id: 'review',
    title: 'Review layout',
    priority: TaskPriority.low,
    isDone: true,
    createdAt: DateTime(2026, 10, 8),
  ),
  TaskModel(
    id: 'plan',
    title: 'Plan tomorrow',
    priority: TaskPriority.medium,
    createdAt: DateTime(2026, 10, 7),
  ),
];

Finder get _search => find.descendant(
  of: find.widgetWithText(AppTextField, AppStrings.searchTasks),
  matching: find.byType(TextField),
);
Finder _status(String label) => find.widgetWithText(ChoiceChip, label);
Finder _priority(String label) => find.widgetWithText(FilterChip, label);
Finder _tile(String id) => find.byKey(ValueKey(id));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<_TaskCubit> _pumpTab(
  WidgetTester tester, {
  TaskState? state,
  _TaskCubit? cubit,
  AuthState? authState,
  int hour = 9,
  Size size = const Size(800, 1000),
  Brightness brightness = Brightness.light,
  List<RouteSettings>? openedRoutes,
  bool active = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final tasks =
      cubit ??
      _TaskCubit(state ?? TaskState(status: TaskStatus.success, tasks: _tasks));
  final auth = _AuthCubit();
  when(() => auth.state).thenReturn(
    authState ??
        Authenticated(
          UserModel(
            id: 'alex',
            name: '  Alex   Doe  ',
            email: 'alex@example.com',
            createdAt: DateTime(2026, 10, 9),
          ),
        ),
  );
  addTearDown(tasks.close);
  addTearDown(auth.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<TaskCubit>.value(value: tasks),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: TasksTab(
            now: () => DateTime(2026, 10, 9, hour),
            active: active,
          ),
        ),
        onGenerateRoute: (settings) {
          openedRoutes?.add(settings);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(settings.name!)),
              body: Text('Destination ${settings.name}: ${settings.arguments}'),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  if (tasks.state.status != TaskStatus.loading &&
      tasks.state.status != TaskStatus.initial) {
    await tester.pumpAndSettle();
  }
  return tasks;
}

void main() {
  for (final (hour, period) in [
    (11, AppStrings.morning),
    (12, AppStrings.afternoon),
    (17, AppStrings.evening),
  ]) {
    testWidgets('greeting uses the first name at the $period boundary', (
      tester,
    ) async {
      await _pumpTab(tester, hour: hour);
      expect(find.text(AppStrings.greeting(period, 'Alex')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unauthenticated greeting and loading state remain usable', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      state: TaskState(status: TaskStatus.loading),
      authState: const Unauthenticated(),
    );
    expect(find.text(AppStrings.welcomeBack), findsOneWidget);
    expect(find.byType(LoadingView), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state CTA opens the add task route', (tester) async {
    await _pumpTab(tester, state: TaskState(status: TaskStatus.success));
    expect(find.text(AppStrings.noTasksTitle), findsOneWidget);
    await _tapVisible(
      tester,
      find.widgetWithText(AppButton, AppStrings.addTask),
    );
    expect(find.text('Destination ${Routes.taskForm}: null'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no results CTA clears search and both filters', (tester) async {
    final cubit = await _pumpTab(
      tester,
      state: TaskState(
        status: TaskStatus.success,
        tasks: _tasks,
        query: 'missing',
        statusFilter: TaskStatusFilter.done,
        priorityFilter: TaskPriority.high,
      ),
    );
    expect(find.text(AppStrings.noResultsTitle), findsOneWidget);
    expect(tester.widget<TextField>(_search).controller!.text, 'missing');
    await _tapVisible(
      tester,
      find.widgetWithText(AppButton, AppStrings.clearFilters),
    );
    expect(cubit.clearCalls, 1);
    expect(cubit.state.query, isEmpty);
    expect(cubit.state.statusFilter, TaskStatusFilter.all);
    expect(cubit.state.priorityFilter, isNull);
    expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
    expect(find.text(_tasks.first.title), findsOneWidget);
  });

  testWidgets('friendly error retries the repository load', (tester) async {
    final cubit = await _pumpTab(
      tester,
      state: TaskState(
        status: TaskStatus.failure,
        errorMessage: AppStrings.storageError,
      ),
    );
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(AppStrings.storageError), findsOneWidget);
    await _tapVisible(tester, find.widgetWithText(AppButton, AppStrings.retry));
    expect(cubit.loadCalls, 1);
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text(AppStrings.noTasksTitle), findsOneWidget);
  });

  testWidgets('search waits 400 milliseconds and replaces rapid edits', (
    tester,
  ) async {
    final cubit = await _pumpTab(tester);
    await tester.tap(_search);
    await tester.pumpAndSettle();
    await tester.enterText(_search, 'write');
    await tester.pump(const Duration(milliseconds: 200));
    expect(cubit.queries, isEmpty);
    await tester.enterText(_search, 'KEYBOARD');
    await tester.pump(const Duration(milliseconds: 399));
    expect(cubit.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(cubit.queries, ['KEYBOARD']);
    await tester.pumpAndSettle();
    expect(find.text(_tasks.first.title), findsOneWidget);
    expect(find.text(_tasks[1].title), findsNothing);
    expect(find.text(_tasks[2].title), findsNothing);
  });

  testWidgets('clear search cancels a pending edit and keeps its controller', (
    tester,
  ) async {
    final cubit = await _pumpTab(tester);
    final controller = tester.widget<TextField>(_search).controller;
    await tester.tap(_search);
    await tester.pumpAndSettle();
    await tester.enterText(_search, 'stale');
    await tester.pump();
    await tester.tap(find.byTooltip(AppStrings.clearSearch));
    await tester.pump();
    expect(cubit.queries, ['']);
    await tester.pump(const Duration(milliseconds: 500));
    expect(cubit.queries, ['']);
    expect(tester.widget<TextField>(_search).controller, same(controller));
    expect(controller!.text, isEmpty);
    cubit.publish(cubit.state.copyWith(query: 'review'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_search).controller, same(controller));
    expect(controller.text, 'review');
    expect(find.text(_tasks[1].title), findsOneWidget);
  });

  testWidgets(
    'status and priority filters combine and selected priority clears',
    (tester) async {
      final cubit = await _pumpTab(tester);
      await _tapVisible(tester, _status(AppStrings.pending));
      expect(cubit.statuses, [TaskStatusFilter.pending]);
      expect(find.text(_tasks[1].title), findsNothing);
      await _tapVisible(tester, _priority(AppStrings.priorityHigh));
      expect(cubit.priorities, [TaskPriority.high]);
      expect(find.text(_tasks.first.title), findsOneWidget);
      expect(find.text(_tasks[2].title), findsNothing);
      expect(
        tester.widget<FilterChip>(_priority(AppStrings.priorityHigh)).selected,
        isTrue,
      );
      await _tapVisible(tester, _priority(AppStrings.priorityHigh));
      expect(cubit.priorities, [TaskPriority.high, null]);
      expect(find.text(_tasks[2].title), findsOneWidget);
      await _tapVisible(tester, _status(AppStrings.done));
      expect(find.text(_tasks[1].title), findsOneWidget);
      expect(find.text(_tasks.first.title), findsNothing);
    },
  );

  testWidgets('list details carries identity and FAB opens a new task', (
    tester,
  ) async {
    await _pumpTab(tester);
    await _tapVisible(
      tester,
      find.widgetWithText(TaskCard, _tasks.first.title),
    );
    expect(
      find.text('Destination ${Routes.taskDetails}: ${_tasks.first.id}'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byType(FloatingActionButton));
    expect(find.text('Destination ${Routes.taskForm}: null'), findsOneWidget);
  });

  testWidgets('rapid FAB callbacks open one form and release after returning', (
    tester,
  ) async {
    final openedRoutes = <RouteSettings>[];
    await _pumpTab(tester, openedRoutes: openedRoutes);
    final open = tester
        .widget<FloatingActionButton>(find.byType(FloatingActionButton))
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(openedRoutes.map((route) => route.name), [Routes.taskForm]);
    expect(find.text('Destination ${Routes.taskForm}: null'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TasksTab), findsOneWidget);
    expect(find.text('Destination ${Routes.taskForm}: null'), findsNothing);
    await _tapVisible(tester, find.byType(FloatingActionButton));
    expect(openedRoutes.map((route) => route.name), [
      Routes.taskForm,
      Routes.taskForm,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid keyboard changes allow Add before FAB transitions settle',
    (tester) async {
      final openedRoutes = <RouteSettings>[];
      await _pumpTab(tester, openedRoutes: openedRoutes);
      await tester.tap(_search);
      await tester.pumpAndSettle();
      addTearDown(tester.view.resetViewInsets);
      for (final bottom in [260.0, 0.0, 260.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottom);
        await tester.pump(const Duration(milliseconds: 16));
      }
      final add = tester
          .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
          .last
          .onPressed!;
      add();
      await tester.pumpAndSettle();
      expect(openedRoutes.map((route) => route.name), [Routes.taskForm]);
      expect(find.text('Destination ${Routes.taskForm}: null'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('checkbox toggles completion and loading disables mutations', (
    tester,
  ) async {
    final cubit = await _pumpTab(tester);
    final checkbox = find.descendant(
      of: _tile(_tasks.first.id),
      matching: find.byType(Checkbox),
    );
    await _tapVisible(tester, checkbox);
    expect(cubit.toggledIds, [_tasks.first.id]);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    cubit.publish(cubit.state.copyWith(status: TaskStatus.loading));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(_tasks.first.title), findsOneWidget);
    expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
    expect(
      tester.widget<Dismissible>(_tile(_tasks.first.id)).direction,
      DismissDirection.none,
    );
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
  });

  testWidgets('actual swipe deletes and Undo restores the exact task', (
    tester,
  ) async {
    final cubit = await _pumpTab(tester);
    await tester.drag(_tile(_tasks.first.id), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(cubit.deletedIds, [_tasks.first.id]);
    expect(find.text(_tasks.first.title), findsNothing);
    expect(find.text(AppStrings.taskDeleted), findsOneWidget);
    await _tapVisible(
      tester,
      find.widgetWithText(SnackBarAction, AppStrings.undo),
    );
    expect(cubit.undoCalls, 1);
    expect(cubit.state.tasks.last, same(_tasks.first));
    expect(find.text(_tasks.first.title), findsOneWidget);
    expect(cubit.state.lastDeleted, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo snackbar expires without restoring the deleted task', (
    tester,
  ) async {
    final cubit = await _pumpTab(tester);
    await tester.drag(_tile(_tasks.first.id), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SnackBarAction, AppStrings.undo),
      findsOneWidget,
    );
    expect(cubit.state.lastDeleted, same(_tasks.first));
    await tester.pump(AppConstants.undoDuration);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.widgetWithText(SnackBarAction, AppStrings.undo), findsNothing);
    expect(cubit.undoCalls, 0);
    expect(cubit.state.lastDeleted, same(_tasks.first));
    expect(find.text(_tasks.first.title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo waits for another mutation and restores its snapshot', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cubit = _TaskCubit(
      TaskState(status: TaskStatus.success, tasks: _tasks),
    )..pendingToggle = pending;
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    await _pumpTab(tester, cubit: cubit);
    await tester.drag(_tile(_tasks.first.id), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(cubit.state.lastDeleted, same(_tasks.first));

    final checkbox = find.descendant(
      of: _tile(_tasks[1].id),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pump(const Duration(milliseconds: 16));
    expect(cubit.state.status, TaskStatus.loading);
    expect(cubit.toggledIds, [_tasks[1].id]);

    await tester.tap(find.widgetWithText(SnackBarAction, AppStrings.undo));
    await tester.pump(const Duration(milliseconds: 16));
    expect(cubit.undoCalls, 0);
    expect(cubit.state.lastDeleted, same(_tasks.first));
    expect(
      cubit.state.tasks.any((task) => task.id == _tasks.first.id),
      isFalse,
    );

    pending.complete();
    await tester.pumpAndSettle();
    expect(cubit.undoCalls, 1);
    expect(cubit.state.status, TaskStatus.success);
    expect(cubit.state.tasks.last, same(_tasks.first));
    expect(
      cubit.state.tasks.singleWhere((task) => task.id == _tasks[1].id).isDone,
      isFalse,
    );
    expect(cubit.state.lastDeleted, isNull);
    expect(find.text(_tasks.first.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed Undo offers another user retry and preserves its snapshot',
    (tester) async {
      final cubit = _TaskCubit(
        TaskState(status: TaskStatus.success, tasks: _tasks),
      )..failUndo = true;
      await _pumpTab(tester, cubit: cubit);
      await tester.drag(_tile(_tasks.first.id), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(cubit.deletedIds, [_tasks.first.id]);
      expect(find.text(_tasks.first.title), findsNothing);
      await _tapVisible(
        tester,
        find.widgetWithText(SnackBarAction, AppStrings.undo),
      );
      expect(cubit.undoCalls, 1);
      expect(cubit.state.status, TaskStatus.failure);
      expect(cubit.state.lastDeleted, same(_tasks.first));
      expect(find.text(_tasks.first.title), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(AppStrings.storageError),
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SnackBarAction, AppStrings.undo),
        findsOneWidget,
      );
      cubit.failUndo = false;
      await _tapVisible(
        tester,
        find.widgetWithText(SnackBarAction, AppStrings.undo),
      );
      expect(cubit.undoCalls, 2);
      expect(cubit.state.status, TaskStatus.success);
      expect(cubit.state.lastDeleted, isNull);
      expect(cubit.state.tasks.last, same(_tasks.first));
      expect(find.text(_tasks.first.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inactive My Tasks retains errors without a snackbar', (
    tester,
  ) async {
    final cubit = await _pumpTab(tester, active: false);
    cubit.publish(
      cubit.state.copyWith(
        status: TaskStatus.failure,
        errorMessage: AppStrings.storageError,
      ),
    );
    await tester.pumpAndSettle();
    expect(cubit.state.tasks, _tasks);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(AppStrings.storageError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed swipe retains the task and shows a friendly error', (
    tester,
  ) async {
    final cubit = _TaskCubit(
      TaskState(status: TaskStatus.success, tasks: _tasks),
    )..failDelete = true;
    await _pumpTab(tester, cubit: cubit);
    await tester.drag(_tile(_tasks.first.id), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(cubit.deletedIds, [_tasks.first.id]);
    expect(cubit.state.tasks, _tasks);
    expect(find.text(_tasks.first.title), findsOneWidget);
    for (final task in _tasks) {
      expect(_tile(task.id), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(AppStrings.storageError),
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.taskDeleted), findsNothing);
    expect(find.widgetWithText(SnackBarAction, AppStrings.undo), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull to refresh waits for the pending load and keeps the list', (
    tester,
  ) async {
    final cubit = _TaskCubit(
      TaskState(status: TaskStatus.success, tasks: _tasks),
    );
    final pending = Completer<void>();
    cubit.pendingLoad = pending;
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    await _pumpTab(tester, cubit: cubit);
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final gesture = await tester.startGesture(
      Offset(viewport.center.dx, viewport.top + 24),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 550));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(cubit.loadCalls, 1);
    expect(cubit.state.status, TaskStatus.loading);
    expect(find.text(_tasks.first.title), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(cubit.state.status, TaskStatus.success);
    expect(find.text(_tasks.first.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} narrow large-text layout accepts keyboard search without overflow',
      (tester) async {
        final cubit = await _pumpTab(
          tester,
          size: const Size(320, 568),
          brightness: brightness,
        );
        await _tapVisible(tester, _search);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.enterText(_search, 'release');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(cubit.queries, ['release']);
        expect(tester.widget<TextField>(_search).controller!.text, 'release');
        expect(tester.takeException(), isNull);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.ensureVisible(_tile(_tasks.first.id));
        await tester.pumpAndSettle();
        expect(find.text(_tasks.first.title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'nested scaffold hides FAB for the keyboard and keeps clear search accessible',
    (tester) async {
      final cubit = await _pumpTab(tester, size: const Size(320, 568));
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await _tapVisible(tester, _search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.enterText(_search, 'release');
      await tester.pump();
      await _tapVisible(tester, find.byTooltip(AppStrings.clearSearch));
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(cubit.queries.last, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing the tab cancels its pending search callback', (
    tester,
  ) async {
    final cubit = await _pumpTab(tester);
    await tester.tap(_search);
    await tester.pumpAndSettle();
    await tester.enterText(_search, 'pending');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    expect(cubit.queries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
