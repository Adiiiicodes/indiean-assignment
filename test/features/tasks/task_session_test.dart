import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';
import 'package:dio/dio.dart';
import 'package:focusdesk/data/models/suggested_page_model.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SessionTasks extends TaskRepository {
  _SessionTasks() : super(TaskLocalDatasource(HiveService()));
  int reads = 0;
  Completer<List<TaskModel>>? pending;
  final saved = TaskModel(id: 'saved', title: 'Saved session task');

  @override
  Future<List<TaskModel>> getTasks() async {
    reads++;
    if (pending != null) return pending!.future;
    return [saved];
  }
}

class _SessionSuggested extends SuggestedRepository {
  _SessionSuggested() : super(SuggestedRemoteDatasource(Dio()));
  int reads = 0;

  @override
  Future<SuggestedPageModel> fetch({int limit = 20, int skip = 0}) async {
    reads++;
    return SuggestedPageModel(
      todos: const [
        SuggestedTaskModel(
          id: 1,
          todo: 'Session suggestion',
          completed: false,
          userId: 1,
        ),
      ],
      total: 1,
      skip: 0,
      limit: 1,
    );
  }
}

Future<(AuthCubit, TaskCubit)> _mount(
  WidgetTester tester,
  _SessionTasks tasks, {
  bool savedSession = false,
  SuggestedRepository? suggested,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = PrefsService(await SharedPreferences.getInstance());
  final auth = AuthRepository(AuthLocalDatasource(prefs), delay: Duration.zero);
  final initialization = auth.initialize();
  await tester.pump();
  await initialization;
  if (savedSession) {
    final login = auth.login(
      email: AppConstants.demoEmail,
      password: AppConstants.demoPassword,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await login;
  }
  await tester.pumpWidget(
    FocusDeskApp(
      dependencies: AppDependencies(
        prefs: prefs,
        hive: HiveService(),
        auth: auth,
        tasks: tasks,
        suggested: suggested,
      ),
    ),
  );
  await tester.pump(AppConstants.splashDuration);
  await tester.pumpAndSettle();
  final context = tester.element(
    find.byType(savedSession ? HomeScreen : LoginScreen),
  );
  return (context.read<AuthCubit>(), context.read<TaskCubit>());
}

Future<void> _login(WidgetTester tester, AuthCubit auth) async {
  final login = auth.login(
    email: AppConstants.demoEmail,
    password: AppConstants.demoPassword,
  );
  await tester.pump(const Duration(milliseconds: 1));
  await login;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('suggestions share app scope and reset cache across logout', (
    tester,
  ) async {
    final repository = _SessionSuggested();
    final (auth, _) = await _mount(
      tester,
      _SessionTasks(),
      suggested: repository,
    );
    await _login(tester, auth);
    final suggestions = tester
        .element(find.byType(HomeScreen))
        .read<SuggestedCubit>();
    expect(repository.reads, 0);
    await suggestions.load();
    await tester.pumpAndSettle();
    expect(suggestions.state.items.single.todo, 'Session suggestion');
    final refresh = auth.refreshUser();
    await tester.pump();
    await refresh;
    await tester.pumpAndSettle();
    expect(suggestions.state.items, hasLength(1));
    final logout = auth.logout();
    await tester.pump();
    await logout;
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(LoginScreen)).read<SuggestedCubit>(),
      same(suggestions),
    );
    expect(suggestions.state.status, SuggestedStatus.initial);
    expect(suggestions.state.items, isEmpty);
    expect(suggestions.state.importedIds, isEmpty);
    await _login(tester, auth);
    expect(
      tester.element(find.byType(HomeScreen)).read<SuggestedCubit>(),
      same(suggestions),
    );
    expect(repository.reads, 1);
    await suggestions.load();
    await tester.pumpAndSettle();
    expect(repository.reads, 2);
    expect(suggestions.state.items, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(suggestions.isClosed, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved-session startup loads shared tasks once', (tester) async {
    final repository = _SessionTasks();
    final (_, tasks) = await _mount(tester, repository, savedSession: true);
    expect(repository.reads, 1);
    expect(tasks.state.tasks, [repository.saved]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shared task state loads on login and resets on logout', (
    tester,
  ) async {
    final repository = _SessionTasks();
    final (auth, tasks) = await _mount(tester, repository);
    expect(repository.reads, 0);
    await _login(tester, auth);
    expect(repository.reads, 1);
    expect(tasks.state.tasks, [repository.saved]);
    expect(
      tester.element(find.byType(HomeScreen)).read<TaskCubit>(),
      same(tasks),
    );
    final refresh = auth.refreshUser();
    await tester.pump();
    await refresh;
    await tester.pumpAndSettle();
    expect(repository.reads, 1);
    tasks.setQuery('saved');
    final logout = auth.logout();
    await tester.pump();
    await logout;
    await tester.pumpAndSettle();
    expect(tasks.state.tasks, isEmpty);
    expect(tasks.state.query, isEmpty);
    expect(
      tester.element(find.byType(LoginScreen)).read<TaskCubit>(),
      same(tasks),
    );
    await _login(tester, auth);
    expect(repository.reads, 2);
    expect(tasks.state.tasks, [repository.saved]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tasks.isClosed, isTrue);
  });

  testWidgets('logout ignores a task load that finishes after session reset', (
    tester,
  ) async {
    final repository = _SessionTasks()..pending = Completer<List<TaskModel>>();
    final (auth, tasks) = await _mount(tester, repository);
    await _login(tester, auth);
    expect(repository.reads, 1);
    final logout = auth.logout();
    await tester.pump();
    await logout;
    await tester.pumpAndSettle();
    repository.pending!.complete([repository.saved]);
    await tester.pumpAndSettle();
    expect(tasks.state.tasks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a replacement session invalidates the previous pending read', (
    tester,
  ) async {
    final oldRead = Completer<List<TaskModel>>();
    final repository = _SessionTasks()..pending = oldRead;
    final (auth, tasks) = await _mount(tester, repository);
    await _login(tester, auth);
    tasks.setQuery('old filter');
    final newRead = Completer<List<TaskModel>>();
    repository.pending = newRead;
    final replacement = auth.signUp(
      name: 'Replacement User',
      email: 'replacement@example.com',
      password: 'Replacement@123',
    );
    await tester.pump(const Duration(milliseconds: 1));
    await replacement;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.reads, 2);
    expect(tasks.state.query, isEmpty);
    oldRead.complete([repository.saved]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tasks.state.tasks, isEmpty);
    final newTask = TaskModel(id: 'replacement', title: 'Current session task');
    newRead.complete([newTask]);
    await tester.pumpAndSettle();
    expect(tasks.state.tasks, [newTask]);
    expect(tester.takeException(), isNull);
  });
}
