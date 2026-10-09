import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:focusdesk/features/tasks/view/task_form_screen.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:mocktail/mocktail.dart';

class _AuthenticatedCubit extends MockCubit<AuthState> implements AuthCubit {}

class _MemoryTasks extends TaskLocalDatasource {
  _MemoryTasks() : super(HiveService());
  final _saved = <String, TaskModel>{};

  @override
  Future<List<TaskModel>> getTasks() async => _saved.values.toList();
  @override
  Future<TaskModel?> getById(String id) async => _saved[id];
  @override
  Future<void> put(TaskModel task) async {
    _saved[task.id] = task;
  }

  @override
  Future<void> delete(String id) async {
    _saved.remove(id);
  }

  @override
  Future<void> clear() async => _saved.clear();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
);
Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == label,
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(_field(label));
  await tester.pumpAndSettle();
  await tester.enterText(_field(label), value);
  await tester.pumpAndSettle();
}

Future<void> _finishStorage(WidgetTester tester, TaskCubit cubit) async {
  await tester.pump();
  await tester.pumpAndSettle();
  expect(cubit.state.status, TaskStatus.success);
  expect(tester.takeException(), isNull);
}

Future<void> _create(
  WidgetTester tester,
  TaskCubit cubit, {
  required String title,
  required String description,
  required TaskPriority priority,
}) async {
  await _tapVisible(tester, find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  expect(find.byType(TaskFormScreen), findsOneWidget);
  expect(
    tester.element(find.byType(TaskFormScreen)).read<TaskCubit>(),
    same(cubit),
  );
  await _enter(tester, AppStrings.title, title);
  await _enter(tester, AppStrings.description, description);
  await _tapVisible(
    tester,
    find.descendant(
      of: find.byType(SegmentedButton<TaskPriority>),
      matching: find.text(priority.label),
    ),
  );
  await _tapVisible(tester, _button(AppStrings.save));
  await _finishStorage(tester, cubit);
  expect(find.byType(TaskFormScreen), findsNothing);
  expect(find.byType(HomeScreen), findsOneWidget);
}

void main() {
  testWidgets(
    'real router and repository preserve the complete create/filter/edit/delete/Undo flow',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = DateTime.now().add(const Duration(hours: 1));
      final repository = TaskRepository(_MemoryTasks(), now: () => now);
      final cubit = TaskCubit(repository);
      final auth = _AuthenticatedCubit();
      when(() => auth.state).thenReturn(
        Authenticated(
          UserModel(
            id: 'flow-user',
            name: 'Alex Doe',
            email: 'alex@example.com',
            createdAt: DateTime(2026, 10, 9),
          ),
        ),
      );
      addTearDown(cubit.close);
      addTearDown(auth.close);
      await cubit.load();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: auth),
            BlocProvider<TaskCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            initialRoute: Routes.home,
            onGenerateInitialRoutes: (_) => [
              AppRouter.onGenerateRoute(const RouteSettings(name: Routes.home)),
            ],
            onGenerateRoute: AppRouter.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noTasksTitle), findsOneWidget);
      await _create(
        tester,
        cubit,
        title: 'Alpha design',
        description: 'Review KEYBOARD flows',
        priority: TaskPriority.low,
      );
      await _create(
        tester,
        cubit,
        title: 'Beta service',
        description: 'Check network responses',
        priority: TaskPriority.high,
      );
      await _create(
        tester,
        cubit,
        title: 'Gamma release',
        description: 'Prepare documentation',
        priority: TaskPriority.medium,
      );
      final saved = await repository.getTasks();
      expect(saved, hasLength(3));
      expect(saved.map((task) => task.id).toSet(), hasLength(3));
      expect(
        saved.every((task) => task.source == TaskSource.local && !task.isDone),
        isTrue,
      );
      final alpha = saved.singleWhere((task) => task.title == 'Alpha design');
      expect(alpha.priority, TaskPriority.low);

      await _enter(tester, AppStrings.searchTasks, 'keyboard');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, AppStrings.pending),
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilterChip, AppStrings.priorityLow),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TaskCard, alpha.title), findsOneWidget);
      expect(find.widgetWithText(TaskCard, 'Beta service'), findsNothing);
      expect(find.widgetWithText(TaskCard, 'Gamma release'), findsNothing);
      expect(cubit.state.visibleTasks.single.id, alpha.id);

      await _tapVisible(tester, find.text(alpha.title));
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(TaskDetailsScreen)).read<TaskCubit>(),
        same(cubit),
      );
      await _tapVisible(tester, find.byTooltip(AppStrings.edit));
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(TaskFormScreen)).read<TaskCubit>(),
        same(cubit),
      );
      await _enter(tester, AppStrings.title, 'Alpha updated');
      await _enter(
        tester,
        AppStrings.description,
        'Updated KEYBOARD checklist',
      );
      await _tapVisible(
        tester,
        find.descendant(
          of: find.byType(SegmentedButton<TaskPriority>),
          matching: find.text(AppStrings.priorityHigh),
        ),
      );
      now = now.add(const Duration(minutes: 1));
      await _tapVisible(tester, _button(AppStrings.save));
      await _finishStorage(tester, cubit);
      expect(find.byType(TaskDetailsScreen), findsOneWidget);
      expect(find.text('Alpha updated'), findsOneWidget);
      expect(find.text('Updated KEYBOARD checklist'), findsOneWidget);
      final edited = (await repository.getById(alpha.id))!;
      expect(edited.id, alpha.id);
      expect(edited.createdAt, alpha.createdAt);
      expect(edited.source, alpha.source);
      expect(edited.priority, TaskPriority.high);
      expect(edited.updatedAt.isAfter(alpha.updatedAt), isTrue);
      now = now.add(const Duration(minutes: 1));
      await _tapVisible(tester, _button(AppStrings.markDone));
      await _finishStorage(tester, cubit);
      expect(find.widgetWithText(Chip, AppStrings.done), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noResultsTitle), findsOneWidget);
      expect(cubit.state.query, 'keyboard');
      expect(cubit.state.statusFilter, TaskStatusFilter.pending);
      expect(cubit.state.priorityFilter, TaskPriority.low);
      await _tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, AppStrings.done),
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilterChip, AppStrings.priorityHigh),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TaskCard, 'Alpha updated'), findsOneWidget);
      expect(cubit.state.visibleTasks.single.isDone, isTrue);
      final completed = (await repository.getById(alpha.id))!;

      await _tapVisible(tester, find.text('Alpha updated'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byTooltip(AppStrings.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.delete));
      await tester.pump();
      await _finishStorage(tester, cubit);
      expect(find.byType(TaskDetailsScreen), findsNothing);
      expect(await repository.getById(alpha.id), isNull);
      expect(cubit.state.lastDeleted, completed);
      expect(find.text(AppStrings.taskDeleted), findsOneWidget);
      expect(find.widgetWithText(TaskCard, 'Alpha updated'), findsNothing);
      await _tapVisible(
        tester,
        find.widgetWithText(SnackBarAction, AppStrings.undo),
      );
      await _finishStorage(tester, cubit);
      final restored = await repository.getById(alpha.id);
      expect(restored, completed);
      expect(restored!.toJson(), completed.toJson());
      expect(cubit.state.lastDeleted, isNull);
      expect(cubit.state.query, 'keyboard');
      expect(cubit.state.statusFilter, TaskStatusFilter.done);
      expect(cubit.state.priorityFilter, TaskPriority.high);
      expect(find.widgetWithText(TaskCard, 'Alpha updated'), findsOneWidget);
      expect(await repository.getTasks(), hasLength(3));
      await _tapVisible(tester, find.byTooltip(AppStrings.clearSearch));
      await _tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, AppStrings.all),
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilterChip, AppStrings.allPriorities),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TaskCard), findsNWidgets(3));
      for (var attempt = 0; attempt < 2; attempt++) {
        await _tapVisible(tester, find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(find.byType(TaskFormScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.widgetWithText(TaskCard, 'Alpha updated'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(
        Navigator.of(tester.element(find.byType(HomeScreen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
