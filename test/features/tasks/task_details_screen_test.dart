import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:mocktail/mocktail.dart';

final _task = TaskModel(
  id: 'details-task',
  title: 'Review the release',
  description: 'Read the full checklist.\nCheck the keyboard and every action before sharing.',
  priority: TaskPriority.high,
  dueDate: DateTime.now().subtract(const Duration(days: 2)),
  createdAt: DateTime(2026, 10, 8, 10),
  updatedAt: DateTime(2026, 10, 9, 11),
  source: TaskSource.imported,
);

class _AuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _DetailsCubit extends Cubit<TaskState> implements TaskCubit {
  _DetailsCubit({TaskState? state})
    : super(state ?? TaskState(status: TaskStatus.success, tasks: [_task]));
  final toggled = <String>[];
  final deleted = <String>[];
  int loads = 0;
  int undos = 0;
  Completer<void>? pending;
  bool failDeleteRead = false;
  List<TaskModel>? storedAfterDelete;

  @override
  Future<void> load() async {
    loads++;
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    await Future<void>.value();
    if (!isClosed) {
      emit(
        state.copyWith(
          status: TaskStatus.success,
          tasks: storedAfterDelete ?? state.tasks,
        ),
      );
    }
  }

  @override
  Future<void> toggleDone(String id) async {
    toggled.add(id);
    emit(state.copyWith(status: TaskStatus.loading));
    await pending?.future;
    if (!isClosed) {
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
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    final snapshot = state.tasks.singleWhere((task) => task.id == id);
    emit(state.copyWith(status: TaskStatus.loading));
    await pending?.future;
    if (isClosed) return;
    storedAfterDelete = state.tasks.where((task) => task.id != id).toList();
    emit(
      state.copyWith(
        status: failDeleteRead ? TaskStatus.failure : TaskStatus.success,
        tasks: failDeleteRead ? state.tasks : storedAfterDelete,
        lastDeleted: snapshot,
        errorMessage: failDeleteRead ? AppStrings.storageError : null,
        clearError: !failDeleteRead,
      ),
    );
  }

  @override
  Future<void> undoDelete() async {
    undos++;
    final snapshot = state.lastDeleted;
    if (snapshot != null) {
      final restored = [...(storedAfterDelete ?? state.tasks), snapshot];
      storedAfterDelete = restored;
      emit(
        state.copyWith(
          status: TaskStatus.success,
          tasks: restored,
          clearLastDeleted: true,
          clearError: true,
        ),
      );
    }
  }

  @override
  Future<void> add(TaskModel task) async {}
  @override
  Future<void> update(TaskModel task) async {}
  @override
  void setQuery(String query) => emit(state.copyWith(query: query));
  @override
  void setStatusFilter(TaskStatusFilter filter) =>
      emit(state.copyWith(statusFilter: filter));
  @override
  void setPriorityFilter(TaskPriority? filter) => emit(
    state.copyWith(priorityFilter: filter, clearPriorityFilter: filter == null),
  );
  @override
  void clearFilters() => emit(
    state.copyWith(
      query: '',
      statusFilter: TaskStatusFilter.all,
      clearPriorityFilter: true,
    ),
  );
  @override
  void reset() => emit(TaskState());
}

class _Navigation {
  final destinations = <RouteSettings>[];
  TaskModel? result;
}

Finder _action(String label) => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == label,
);

Finder _iconAction(String label) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == label,
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<_Navigation> _pumpDetails(
  WidgetTester tester,
  _DetailsCubit cubit, {
  String? taskId = 'details-task',
  bool fromTasks = false,
  Size size = const Size(600, 900),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(cubit.close);
  final auth = _AuthCubit();
  when(() => auth.state).thenReturn(
    Authenticated(
      UserModel(
        id: 'demo',
        name: 'Alex Doe',
        email: 'alex@example.com',
        createdAt: DateTime(2026, 10, 9),
      ),
    ),
  );
  addTearDown(auth.close);
  final navigation = _Navigation();
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TaskCubit>.value(value: cubit),
        BlocProvider<AuthCubit>.value(value: auth),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: fromTasks
            ? const Scaffold(body: TasksTab())
            : Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () async {
                        navigation.result = await Navigator.of(context)
                            .pushNamed<TaskModel>(
                              Routes.taskDetails,
                              arguments: taskId,
                            );
                      },
                      child: const Text('Open details'),
                    ),
                  ),
                ),
              ),
        onGenerateRoute: (settings) {
          if (settings.name == Routes.taskDetails) {
            return MaterialPageRoute<TaskModel>(
              settings: settings,
              builder: (_) =>
                  TaskDetailsScreen(taskId: settings.arguments as String?),
            );
          }
          navigation.destinations.add(settings);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(settings.name!)),
              body: const Text('Action destination'),
            ),
          );
        },
      ),
    ),
  );
  if (fromTasks) {
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text(_task.title));
  } else {
    await tester.tap(find.widgetWithText(FilledButton, 'Open details'));
  }
  if (cubit.state.status == TaskStatus.initial ||
      cubit.state.status == TaskStatus.loading) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  } else {
    await tester.pumpAndSettle();
  }
  return navigation;
}

void main() {
  testWidgets(
    'shows full task data and Hero even when list filters exclude it',
    (tester) async {
      final cubit = _DetailsCubit(
        state: TaskState(
          status: TaskStatus.success,
          tasks: [_task],
          query: 'no match',
          statusFilter: TaskStatusFilter.done,
          priorityFilter: TaskPriority.low,
        ),
      );
      await _pumpDetails(tester, cubit);
      expect(cubit.state.visibleTasks, isEmpty);
      expect(find.text(_task.title), findsOneWidget);
      expect(
        tester.widget<Hero>(find.byType(Hero)).tag,
        TaskCard.heroTag(_task.id),
      );
      expect(find.text(_task.description), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(_task.description)).maxLines,
        isNull,
      );
      expect(find.text(AppStrings.priorityHigh), findsOneWidget);
      expect(find.text(AppStrings.imported), findsOneWidget);
      expect(find.widgetWithText(Chip, AppStrings.pending), findsOneWidget);
      expect(find.textContaining(AppStrings.overdue), findsOneWidget);
      expect(
        find.text(AppDateUtils.formatTimestamp(_task.createdAt)),
        findsOneWidget,
      );
      expect(
        find.text(AppDateUtils.formatTimestamp(_task.updatedAt)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('not found offers Retry without presenting stale task data', (
    tester,
  ) async {
    final cubit = _DetailsCubit(state: TaskState(status: TaskStatus.success));
    await _pumpDetails(tester, cubit);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(AppStrings.taskNotFound), findsOneWidget);
    await _tapVisible(tester, _action(AppStrings.retry));
    await tester.pumpAndSettle();
    expect(cubit.loads, 1);
    expect(find.text(AppStrings.taskNotFound), findsOneWidget);
    expect(find.text(_task.title), findsNothing);
  });

  testWidgets('initial read shows LoadingView while no task is available', (
    tester,
  ) async {
    await _pumpDetails(
      tester,
      _DetailsCubit(state: TaskState(status: TaskStatus.loading)),
    );
    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text(_task.title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed refresh retains data and Retry clears the friendly error',
    (tester) async {
      final cubit = _DetailsCubit(
        state: TaskState(
          status: TaskStatus.failure,
          tasks: [_task],
          errorMessage: AppStrings.storageError,
        ),
      );
      await _pumpDetails(tester, cubit);
      expect(find.text(_task.title), findsOneWidget);
      expect(find.text(AppStrings.storageError), findsWidgets);
      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, AppStrings.retry),
      );
      await tester.pumpAndSettle();
      expect(cubit.loads, 1);
      expect(find.text(_task.title), findsOneWidget);
      expect(find.text(AppStrings.storageError), findsNothing);
    },
  );

  testWidgets(
    'toggle reacts in details and completed due date loses overdue warning',
    (tester) async {
      final cubit = _DetailsCubit();
      await _pumpDetails(tester, cubit);
      await _tapVisible(tester, _action(AppStrings.markDone));
      await tester.pumpAndSettle();
      expect(cubit.toggled, [_task.id]);
      expect(find.widgetWithText(Chip, AppStrings.done), findsOneWidget);
      expect(_action(AppStrings.markUndone), findsOneWidget);
      expect(find.textContaining(AppStrings.overdue), findsNothing);
      expect(
        find.text(AppDateUtils.formatDate(_task.dueDate!)),
        findsOneWidget,
      );
      await _tapVisible(tester, _action(AppStrings.markUndone));
      await tester.pumpAndSettle();
      expect(cubit.toggled, [_task.id, _task.id]);
      expect(find.widgetWithText(Chip, AppStrings.pending), findsOneWidget);
    },
  );

  testWidgets('Edit and Start Focus pass the current typed TaskModel', (
    tester,
  ) async {
    final navigation = await _pumpDetails(tester, _DetailsCubit());
    await _tapVisible(tester, find.byTooltip(AppStrings.edit));
    await tester.pumpAndSettle();
    expect(navigation.destinations.last.name, Routes.taskForm);
    expect(navigation.destinations.last.arguments, same(_task));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapVisible(tester, _action(AppStrings.startFocus));
    await tester.pumpAndSettle();
    expect(navigation.destinations.last.name, Routes.focus);
    expect(navigation.destinations.last.arguments, same(_task));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delete cancellation keeps data and confirmation pops its exact snapshot',
    (tester) async {
      final cubit = _DetailsCubit();
      final navigation = await _pumpDetails(tester, cubit);
      await _tapVisible(tester, find.byTooltip(AppStrings.delete));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.deleteTaskTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, AppStrings.cancel));
      await tester.pumpAndSettle();
      expect(cubit.deleted, isEmpty);
      expect(find.byType(TaskDetailsScreen), findsOneWidget);
      await _tapVisible(tester, find.byTooltip(AppStrings.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.delete));
      await tester.pumpAndSettle();
      expect(cubit.deleted, [_task.id]);
      expect(cubit.state.tasks, isEmpty);
      expect(navigation.result, same(_task));
      expect(find.byType(TaskDetailsScreen), findsNothing);
      expect(find.text('Open details'), findsOneWidget);
    },
  );

  testWidgets(
    'pending delete disables actions, queued delete and Android Back',
    (tester) async {
      final cubit = _DetailsCubit();
      final pending = Completer<void>();
      cubit.pending = pending;
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      await _pumpDetails(tester, cubit);
      final queuedDelete = tester
          .widget<IconButton>(_iconAction(AppStrings.delete))
          .onPressed!;
      await _tapVisible(tester, find.byTooltip(AppStrings.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.delete));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(cubit.deleted, [_task.id]);
      expect(
        tester.widget<IconButton>(_iconAction(AppStrings.edit)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_iconAction(AppStrings.delete)).onPressed,
        isNull,
      );
      expect(
        tester.widget<AppButton>(_action(AppStrings.startFocus)).onPressed,
        isNull,
      );
      queuedDelete();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(TaskDetailsScreen), findsOneWidget);
      expect(find.text(AppStrings.deleteTaskTitle), findsNothing);
      expect(cubit.deleted, [_task.id]);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real Tasks tab receives details deletion and Undo restores its exact task',
    (tester) async {
      final cubit = _DetailsCubit();
      await _pumpDetails(tester, cubit, fromTasks: true);
      await _tapVisible(tester, find.byTooltip(AppStrings.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.delete));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsScreen), findsNothing);
      expect(find.byType(TasksTab), findsOneWidget);
      expect(find.text(AppStrings.taskDeleted), findsOneWidget);
      expect(find.text(_task.title), findsNothing);
      await _tapVisible(
        tester,
        find.widgetWithText(SnackBarAction, AppStrings.undo),
      );
      await tester.pumpAndSettle();
      expect(cubit.undos, 1);
      expect(cubit.state.tasks.single, same(_task));
      expect(cubit.state.lastDeleted, isNull);
      expect(find.widgetWithText(TaskCard, _task.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'committed deletion with failed reread retains details until Retry returns its snapshot',
    (tester) async {
      final cubit = _DetailsCubit()..failDeleteRead = true;
      final navigation = await _pumpDetails(tester, cubit);
      await _tapVisible(tester, find.byTooltip(AppStrings.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.delete));
      await tester.pumpAndSettle();
      expect(cubit.deleted, [_task.id]);
      expect(cubit.state.status, TaskStatus.failure);
      expect(cubit.state.lastDeleted, same(_task));
      expect(cubit.storedAfterDelete, isEmpty);
      expect(find.byType(TaskDetailsScreen), findsOneWidget);
      expect(find.text(_task.title), findsOneWidget);
      expect(find.text(AppStrings.storageError), findsNWidgets(2));
      expect(navigation.result, isNull);
      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, AppStrings.retry),
      );
      await tester.pumpAndSettle();
      expect(cubit.loads, 1);
      expect(cubit.deleted, [_task.id]);
      expect(cubit.state.tasks, isEmpty);
      expect(navigation.result, same(_task));
      expect(find.byType(TaskDetailsScreen), findsNothing);
      expect(find.text('Open details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back after a committed deletion failure offers Undo on the real task list',
    (tester) async {
      final cubit = _DetailsCubit()..failDeleteRead = true;
      await _pumpDetails(tester, cubit, fromTasks: true);
      await _tapVisible(tester, find.byTooltip(AppStrings.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.delete));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsScreen), findsOneWidget);
      expect(cubit.state.status, TaskStatus.failure);
      expect(cubit.storedAfterDelete, isEmpty);
      expect(
        find.widgetWithText(SnackBarAction, AppStrings.undo),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsScreen), findsNothing);
      expect(find.byType(TasksTab), findsOneWidget);
      expect(
        find.widgetWithText(SnackBarAction, AppStrings.undo),
        findsOneWidget,
      );
      final undoBar = find.ancestor(
        of: find.widgetWithText(SnackBarAction, AppStrings.undo),
        matching: find.byType(SnackBar),
      );
      expect(
        find.descendant(
          of: undoBar,
          matching: find.text(AppStrings.storageError),
        ),
        findsOneWidget,
      );
      await _tapVisible(
        tester,
        find.widgetWithText(SnackBarAction, AppStrings.undo),
      );
      await tester.pumpAndSettle();
      expect(cubit.undos, 1);
      expect(cubit.state.status, TaskStatus.success);
      expect(cubit.state.tasks.single, same(_task));
      expect(cubit.state.lastDeleted, isNull);
      expect(find.widgetWithText(TaskCard, _task.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} full details scroll at320px with large text',
      (tester) async {
        final task = _task.copyWith(
          title: 'Review the full accessible release and all user interactions',
          description: '${_task.description}\n${'More useful context. ' * 12}',
        );
        await _pumpDetails(
          tester,
          _DetailsCubit(
            state: TaskState(status: TaskStatus.success, tasks: [task]),
          ),
          size: const Size(320, 568),
          brightness: brightness,
        );
        expect(find.text(task.title), findsOneWidget);
        expect(
          tester.widget<Text>(find.text(task.description)).maxLines,
          isNull,
        );
        await tester.ensureVisible(_action(AppStrings.startFocus));
        await tester.pumpAndSettle();
        expect(_action(AppStrings.startFocus), findsOneWidget);
        final button = tester.getRect(_action(AppStrings.startFocus));
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
