import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/task_form_screen.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class _FormCubit extends Cubit<TaskState> implements TaskCubit {
  _FormCubit([TaskModel? initial])
    : super(TaskState(status: TaskStatus.success, tasks: [?initial])) {
    _stored.addAll(state.tasks);
  }

  final added = <TaskModel>[];
  final updated = <TaskModel>[];
  final _stored = <TaskModel>[];
  Completer<void>? pending;
  bool fail = false;
  bool commitOnFailure = false;
  int loadCalls = 0;

  Future<void> _save(TaskModel task, {required bool edit}) async {
    (edit ? updated : added).add(task);
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    await pending?.future;
    if (isClosed) return;
    if (!fail || commitOnFailure) {
      _stored.removeWhere((item) => item.id == task.id);
      _stored.add(task);
    }
    if (fail) {
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
          tasks: _stored,
          clearError: true,
        ),
      );
    }
  }

  @override
  Future<void> add(TaskModel task) => _save(task, edit: false);
  @override
  Future<void> update(TaskModel task) => _save(task, edit: true);
  @override
  Future<void> load() async {
    loadCalls++;
    emit(state.copyWith(status: TaskStatus.loading, clearError: true));
    await Future<void>.value();
    if (!isClosed) {
      emit(state.copyWith(status: TaskStatus.success, tasks: _stored));
    }
  }

  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> toggleDone(String id) async {}
  @override
  Future<void> undoDelete() async {}
  @override
  void setQuery(String query) {}
  @override
  void setStatusFilter(TaskStatusFilter filter) {}
  @override
  void setPriorityFilter(TaskPriority? filter) {}
  @override
  void clearFilters() {}
  @override
  void reset() {}
}

final _existing = TaskModel(
  id: 'imported-42',
  title: 'Review imported task',
  description: 'First line\nSecond line',
  priority: TaskPriority.high,
  dueDate: DateTime(2026, 10, 15),
  isDone: true,
  createdAt: DateTime(2026, 10, 8, 10),
  updatedAt: DateTime(2026, 10, 9, 11),
  source: TaskSource.imported,
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
);
Finder get _save => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == AppStrings.save,
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.pumpAndSettle();
  await tester.enterText(_field(label), text);
  await tester.pumpAndSettle();
}

TextField _textField(WidgetTester tester, String label) =>
    tester.widget<TextField>(
      find.descendant(of: _field(label), matching: find.byType(TextField)),
    );

Future<void> _openForm(
  BuildContext context,
  ValueChanged<TaskModel?>? onResult,
) async {
  final result = await Navigator.of(context).pushNamed(Routes.taskForm);
  if (!context.mounted) return;
  final saved = result is TaskModel ? result : null;
  onResult?.call(saved);
  if (saved != null) {
    AppSnackbar.showSuccess(context, AppStrings.taskSaved);
  }
}

Future<void> _pumpForm(
  WidgetTester tester,
  _FormCubit cubit, {
  TaskModel? task,
  Size size = const Size(600, 900),
  Brightness brightness = Brightness.light,
  ValueChanged<TaskModel?>? onResult,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    BlocProvider<TaskCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => unawaited(_openForm(context, onResult)),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
        routes: {Routes.taskForm: (_) => TaskFormScreen(task: task)},
      ),
    ),
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Open form'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty and short titles show validation without saving', (
    tester,
  ) async {
    final cubit = _FormCubit();
    await _pumpForm(tester, cubit);
    await _tapVisible(tester, _save);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.titleRequired), findsOneWidget);
    expect(cubit.added, isEmpty);
    await _enter(tester, AppStrings.title, 'ab');
    await _tapVisible(tester, _save);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.titleInvalid), findsOneWidget);
    expect(cubit.added, isEmpty);
    expect(find.byType(TaskFormScreen), findsOneWidget);
  });

  testWidgets('description is multiline with the300-character counter', (
    tester,
  ) async {
    await _pumpForm(tester, _FormCubit());
    expect(_textField(tester, AppStrings.description).maxLines, greaterThan(1));
    expect(_textField(tester, AppStrings.description).maxLength, 300);
    final description = 'First line\n${'x' * 289}';
    await _enter(tester, AppStrings.description, description);
    expect(
      _textField(tester, AppStrings.description).controller!.text,
      description,
    );
    expect(find.text('300/300'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'create trims fields and saves a local pending task with default priority',
    (tester) async {
      final cubit = _FormCubit();
      TaskModel? returned;
      await _pumpForm(tester, cubit, onResult: (task) => returned = task);
      expect(_textField(tester, AppStrings.title).autofocus, isTrue);
      expect(find.byType(SwitchListTile), findsNothing);
      await _enter(tester, AppStrings.title, '  Plan the release  ');
      await _enter(
        tester,
        AppStrings.description,
        '  First line\nSecond line  ',
      );
      await _tapVisible(tester, _save);
      await tester.pumpAndSettle();
      expect(cubit.added, hasLength(1));
      final saved = cubit.added.single;
      expect(returned, same(saved));
      expect(saved.title, 'Plan the release');
      expect(saved.description, 'First line\nSecond line');
      expect(saved.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(saved.priority, TaskPriority.medium);
      expect(saved.dueDate, isNull);
      expect(saved.isDone, isFalse);
      expect(saved.source, TaskSource.local);
      expect(cubit.updated, isEmpty);
      expect(find.byType(TaskFormScreen), findsNothing);
      expect(find.text('Open form'), findsOneWidget);
      expect(find.text(AppStrings.taskSaved), findsOneWidget);
    },
  );

  testWidgets(
    'edit prefill updates fields while preserving identity, source and creation',
    (tester) async {
      final cubit = _FormCubit(_existing);
      TaskModel? returned;
      await _pumpForm(
        tester,
        cubit,
        task: _existing,
        onResult: (task) => returned = task,
      );
      expect(
        _textField(tester, AppStrings.title).controller!.text,
        _existing.title,
      );
      expect(
        _textField(tester, AppStrings.description).controller!.text,
        _existing.description,
      );
      expect(
        tester
            .widget<SegmentedButton<TaskPriority>>(
              find.byType(SegmentedButton<TaskPriority>),
            )
            .selected,
        {TaskPriority.high},
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(
        find.text(AppDateUtils.formatDate(_existing.dueDate!)),
        findsOneWidget,
      );
      await _enter(tester, AppStrings.title, '  Updated task title  ');
      await _enter(tester, AppStrings.description, ' Updated notes ');
      await _tapVisible(
        tester,
        find.descendant(
          of: find.byType(SegmentedButton<TaskPriority>),
          matching: find.text(AppStrings.priorityLow),
        ),
      );
      await _tapVisible(tester, find.byTooltip(AppStrings.clearDate));
      await _tapVisible(tester, find.byType(SwitchListTile));
      await _tapVisible(tester, _save);
      await tester.pumpAndSettle();
      expect(cubit.updated, hasLength(1));
      final saved = cubit.updated.single;
      expect(returned, same(saved));
      expect(saved.id, _existing.id);
      expect(saved.createdAt, _existing.createdAt);
      expect(saved.source, TaskSource.imported);
      expect(saved.title, 'Updated task title');
      expect(saved.description, 'Updated notes');
      expect(saved.priority, TaskPriority.low);
      expect(saved.dueDate, isNull);
      expect(saved.isDone, isFalse);
      expect(cubit.added, isEmpty);
      expect(_existing.isDone, isTrue);
      expect(_existing.dueDate, isNotNull);
      expect(find.byType(TaskFormScreen), findsNothing);
    },
  );

  testWidgets(
    'calendar selection displays the date and its clear action removes it',
    (tester) async {
      await _pumpForm(tester, _FormCubit());
      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, AppStrings.chooseDate),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      final now = DateTime.now();
      await tester.tap(
        find
            .descendant(
              of: find.byType(CalendarDatePicker),
              matching: find.text('1'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, AppStrings.done));
      await tester.pumpAndSettle();
      expect(
        find.text(AppDateUtils.formatDate(DateTime(now.year, now.month, 1))),
        findsOneWidget,
      );
      await _tapVisible(tester, find.byTooltip(AppStrings.clearDate));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noDueDate), findsOneWidget);
      expect(find.byTooltip(AppStrings.clearDate), findsNothing);
    },
  );

  testWidgets('dirty Back can keep editing and then discard without saving', (
    tester,
  ) async {
    final cubit = _FormCubit();
    await _pumpForm(tester, cubit);
    await _enter(tester, AppStrings.title, 'Unsaved task');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.discardTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, AppStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormScreen), findsOneWidget);
    expect(
      _textField(tester, AppStrings.title).controller!.text,
      'Unsaved task',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, AppStrings.discard));
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormScreen), findsNothing);
    expect(find.text('Open form'), findsOneWidget);
    expect(cubit.added, isEmpty);
  });

  testWidgets('clean Back pops without a discard dialog', (tester) async {
    await _pumpForm(tester, _FormCubit());
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormScreen), findsNothing);
    expect(find.text(AppStrings.discardTitle), findsNothing);
    expect(find.text('Open form'), findsOneWidget);
  });

  testWidgets('pending save disables fields, duplicate submissions and Back', (
    tester,
  ) async {
    final cubit = _FormCubit();
    final pending = Completer<void>();
    cubit.pending = pending;
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    await _pumpForm(tester, cubit);
    await _enter(tester, AppStrings.title, 'Pending save');
    final queuedSave = tester.widget<AppButton>(_save).onPressed!;
    await _tapVisible(tester, _save);
    await tester.pump(const Duration(milliseconds: 16));
    expect(cubit.added, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: _save, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    expect(_textField(tester, AppStrings.title).enabled, isFalse);
    expect(_textField(tester, AppStrings.description).enabled, isFalse);
    queuedSave();
    await tester.pump();
    expect(cubit.added, hasLength(1));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(TaskFormScreen), findsOneWidget);
    expect(find.text(AppStrings.discardTitle), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormScreen), findsNothing);
    expect(cubit.added, hasLength(1));
  });

  testWidgets(
    'friendly save failure preserves input and permits a successful retry',
    (tester) async {
      final cubit = _FormCubit()..fail = true;
      await _pumpForm(tester, cubit);
      await _enter(tester, AppStrings.title, 'Retry this task');
      await _enter(tester, AppStrings.description, 'Keep my work');
      await _tapVisible(tester, _save);
      await tester.pumpAndSettle();
      expect(cubit.added, hasLength(1));
      expect(find.byType(TaskFormScreen), findsOneWidget);
      expect(find.text(AppStrings.storageError), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(AppStrings.storageError),
        ),
        findsOneWidget,
      );
      expect(
        _textField(tester, AppStrings.title).controller!.text,
        'Retry this task',
      );
      expect(
        _textField(tester, AppStrings.description).controller!.text,
        'Keep my work',
      );
      cubit.fail = false;
      await _tapVisible(tester, _save);
      await tester.pumpAndSettle();
      expect(cubit.added, hasLength(2));
      expect(cubit.loadCalls, 1);
      expect(cubit.added.last.id, cubit.added.first.id);
      expect(cubit.added.last.title, 'Retry this task');
      expect(find.byType(TaskFormScreen), findsNothing);
      expect(find.text(AppStrings.taskSaved), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retry after a committed write and failed reread updates its saved identity',
    (tester) async {
      final cubit = _FormCubit()
        ..fail = true
        ..commitOnFailure = true;
      await _pumpForm(tester, cubit);
      await _enter(tester, AppStrings.title, 'Save this draft once');
      await _tapVisible(tester, _save);
      await tester.pumpAndSettle();
      expect(cubit.added, hasLength(1));
      final draft = cubit.added.single;
      expect(cubit.state.tasks, isEmpty);
      expect(find.byType(TaskFormScreen), findsOneWidget);
      cubit.fail = false;
      await _tapVisible(tester, _save);
      await tester.pumpAndSettle();
      expect(cubit.loadCalls, 1);
      expect(cubit.added, hasLength(1));
      expect(cubit.updated, hasLength(1));
      expect(cubit.updated.single.id, draft.id);
      expect(cubit.state.tasks, hasLength(1));
      expect(cubit.state.tasks.single.id, draft.id);
      expect(find.byType(TaskFormScreen), findsNothing);
      expect(find.text(AppStrings.taskSaved), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} narrow form scrolls with keyboard and large text',
      (tester) async {
        final cubit = _FormCubit();
        await _pumpForm(
          tester,
          cubit,
          size: const Size(320, 568),
          brightness: brightness,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await _enter(tester, AppStrings.title, 'Small screen task');
        await _enter(
          tester,
          AppStrings.description,
          'Multiline notes\nStill visible with the keyboard',
        );
        expect(tester.takeException(), isNull);
        await _tapVisible(tester, _save);
        await tester.pumpAndSettle();
        expect(cubit.added.single.title, 'Small screen task');
        expect(find.byType(TaskFormScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
