import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/suggested/view/suggested_view.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';
import 'package:focusdesk/features/tasks/view/tasks_workspace.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:mocktail/mocktail.dart';

class _AuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _TaskCubit extends MockCubit<TaskState> implements TaskCubit {}

class _SuggestedCubit extends MockCubit<SuggestedState>
    implements SuggestedCubit {}

Finder get _search => find.descendant(
  of: find.widgetWithText(AppTextField, AppStrings.searchTasks),
  matching: find.byType(TextField),
);

Future<void> _select(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

ScrollableState _scrollable(WidgetTester tester, Type view) =>
    tester.state<ScrollableState>(
      find
          .descendant(of: find.byType(view), matching: find.byType(Scrollable))
          .first,
    );

Future<_SuggestedCubit> _pumpWorkspace(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = _AuthCubit();
  when(() => auth.state).thenReturn(const Unauthenticated());
  final tasks = _TaskCubit();
  when(() => tasks.isClosed).thenReturn(false);
  var taskState = TaskState(
    status: TaskStatus.success,
    tasks: [
      for (var i = 1; i <= 20; i++)
        TaskModel(id: 'local-$i', title: 'Keep task $i'),
    ],
  );
  final taskStream = StreamController<TaskState>.broadcast();
  whenListen(tasks, taskStream.stream, initialState: taskState);
  when(() => tasks.setQuery(any())).thenAnswer((invocation) {
    taskState = taskState.copyWith(
      query: invocation.positionalArguments.first as String,
    );
    taskStream.add(taskState);
  });
  final suggested = _SuggestedCubit();
  when(() => suggested.isClosed).thenReturn(false);
  final suggestedStream = StreamController<SuggestedState>.broadcast();
  whenListen(suggested, suggestedStream.stream, initialState: SuggestedState());
  when(() => suggested.load()).thenAnswer((_) async {
    suggestedStream.add(
      SuggestedState(
        status: SuggestedStatus.success,
        items: [
          for (var i = 1; i <= 30; i++)
            SuggestedTaskModel(
              id: i,
              todo: 'Suggested task $i',
              completed: false,
              userId: 1,
            ),
        ],
      ),
    );
  });
  when(() => suggested.loadMore()).thenAnswer((_) async {});
  when(() => suggested.refresh()).thenAnswer((_) async {});
  addTearDown(auth.close);
  addTearDown(tasks.close);
  addTearDown(suggested.close);
  addTearDown(taskStream.close);
  addTearDown(suggestedStream.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<TaskCubit>.value(value: tasks),
        BlocProvider<SuggestedCubit>.value(value: suggested),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const Scaffold(body: TasksWorkspace()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return suggested;
}

void main() {
  testWidgets('suggestions load only on the first visit', (tester) async {
    final suggested = await _pumpWorkspace(tester);
    expect(find.byType(TabBarView), findsOneWidget);
    expect(find.byType(SuggestedView), findsNothing);
    verifyNever(() => suggested.load());
    await _select(tester, AppStrings.suggested);
    expect(find.text('Suggested task 1'), findsOneWidget);
    verify(() => suggested.load()).called(1);
    await _select(tester, AppStrings.myTasks);
    await _select(tester, AppStrings.suggested);
    verifyNever(() => suggested.load());
    verifyNever(() => suggested.loadMore());
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} narrow tabs retain query and both scroll positions',
      (tester) async {
        final suggested = await _pumpWorkspace(tester, brightness: brightness);
        final controller = tester.widget<TextField>(_search).controller!;
        await tester.enterText(_search, 'Keep');
        await tester.pump(AppConstants.searchDebounce);
        await tester.pumpAndSettle();
        final myTasksScroll = _scrollable(tester, TasksTab);
        myTasksScroll.position.jumpTo(400);
        await tester.pumpAndSettle();
        final myTasksOffset = myTasksScroll.position.pixels;
        expect(myTasksOffset, greaterThan(0));

        await _select(tester, AppStrings.suggested);
        expect(_search.hitTestable(), findsNothing);
        final suggestedElement = tester.element(find.byType(SuggestedView));
        final suggestedScroll = _scrollable(tester, SuggestedView);
        suggestedScroll.position.jumpTo(420);
        await tester.pumpAndSettle();
        final suggestedOffset = suggestedScroll.position.pixels;
        expect(suggestedOffset, greaterThan(0));

        await _select(tester, AppStrings.myTasks);
        expect(_scrollable(tester, TasksTab), same(myTasksScroll));
        expect(myTasksScroll.position.pixels, closeTo(myTasksOffset, 0.1));
        expect(
          tester.element(find.byType(TasksTab)).read<TaskCubit>().state.query,
          'Keep',
        );
        myTasksScroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(_search).controller, same(controller));
        expect(controller.text, 'Keep');
        expect(_search.hitTestable(), findsOneWidget);

        await _select(tester, AppStrings.suggested);
        expect(
          tester.element(find.byType(SuggestedView)),
          same(suggestedElement),
        );
        expect(_scrollable(tester, SuggestedView), same(suggestedScroll));
        expect(suggestedScroll.position.pixels, closeTo(suggestedOffset, 0.1));
        expect(_search.hitTestable(), findsNothing);
        verify(() => suggested.load()).called(1);
        verifyNever(() => suggested.loadMore());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
