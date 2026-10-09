import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/datasources/remote/api_client.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_state.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/settings_state.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/suggested/view/suggested_view.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/frozen_stats_cubit.dart';

class _AuthenticatedCubit extends MockCubit<AuthState> implements AuthCubit {}

class _FrozenProfile extends MockCubit<ProfileState> implements ProfileCubit {}

class _FrozenTheme extends MockCubit<ThemeState> implements ThemeCubit {}

class _FrozenSettings extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _MemoryTasks extends TaskLocalDatasource {
  _MemoryTasks() : super(HiveService());
  final records = <String, String>{};
  int writes = 0;

  @override
  Future<List<TaskModel>> getTasks() async => [
    for (final value in records.values)
      TaskModel.fromJson(jsonDecode(value) as Map<String, dynamic>),
  ];

  @override
  Future<TaskModel?> getById(String id) async {
    final value = records[id];
    return value == null
        ? null
        : TaskModel.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> put(TaskModel task) async {
    writes++;
    records[task.id] = jsonEncode(task.toJson());
  }

  @override
  Future<void> delete(String id) async {
    records.remove(id);
  }

  @override
  Future<void> clear() async => records.clear();
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final FutureOr<ResponseBody> Function(RequestOptions) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await reply(options);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _page({int skip = 0, int total = 23}) {
  final remaining = total - skip;
  final count = remaining < 20 ? remaining : 20;
  return {
    'todos': [
      for (var id = skip + 1; id <= skip + count; id++)
        {
          'id': id,
          'todo': id == 1 ? '  API task 1  ' : 'API task $id',
          'completed': id.isOdd,
          'userId': 7,
        },
    ],
    'total': total,
    'skip': skip,
    'limit': count,
  };
}

ResponseBody _response(Object data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Future<(TaskCubit, SuggestedCubit, _MemoryTasks)> _pumpHome(
  WidgetTester tester,
  _Adapter adapter,
) async {
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final local = _MemoryTasks();
  final tasks = TaskCubit(TaskRepository(local));
  final dio = ApiClient(enableLogging: false).dio..httpClientAdapter = adapter;
  final suggestions = SuggestedCubit(
    SuggestedRepository(SuggestedRemoteDatasource(dio)),
    tasks,
  );
  final stats = FrozenStatsCubit();
  addTearDown(stats.close);
  final auth = _AuthenticatedCubit();
  when(() => auth.state).thenReturn(
    Authenticated(
      UserModel(
        id: 'import-user',
        name: 'Alex Doe',
        email: 'alex@example.com',
        createdAt: DateTime(2026, 10, 9),
      ),
    ),
  );
  final profile = _FrozenProfile();
  final theme = _FrozenTheme();
  final settings = _FrozenSettings();
  when(() => profile.state)
      .thenReturn(ProfileState(user: (auth.state as Authenticated).user));
  when(() => theme.state).thenReturn(const ThemeState(mode: ThemeMode.light));
  when(() => settings.state).thenReturn(const SettingsState());
  addTearDown(() async {
    await suggestions.close();
    await tasks.close();
    await auth.close();
    await profile.close();
    await theme.close();
    await settings.close();
    dio.close(force: true);
  });
  await tasks.load();
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<StatsCubit>.value(value: stats),
        BlocProvider<TaskCubit>.value(value: tasks),
        BlocProvider<SuggestedCubit>.value(value: suggestions),
        BlocProvider<ProfileCubit>.value(value: profile),
        BlocProvider<ThemeCubit>.value(value: theme),
        BlocProvider<SettingsCubit>.value(value: settings),
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
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(adapter.requests, isEmpty);
  return (tasks, suggestions, local);
}

Finder _tab(String label) => find.widgetWithText(Tab, label);
Finder _add(int id) => find.byKey(ValueKey('suggested-add-$id'));
Finder _suggestedList() => find.descendant(
  of: find.byType(SuggestedView),
  matching: find.byType(ListView),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _finish(WidgetTester tester, bool Function() finished) async {
  for (var frame = 0; frame < 80 && !finished(); frame++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(finished(), isTrue, reason: 'The real asynchronous flow must finish.');
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'API pages import one persisted task through the real router and shared cubits',
    (tester) async {
      final adapter = _Adapter(
        (request) =>
            _response(_page(skip: request.queryParameters['skip'] as int)),
      );
      final (tasks, suggestions, local) = await _pumpHome(tester, adapter);
      expect(find.text(AppStrings.noTasksTitle), findsOneWidget);
      await _tap(tester, _tab(AppStrings.suggested));
      await _finish(
        tester,
        () => suggestions.state.status == SuggestedStatus.success,
      );
      expect(adapter.requests, hasLength(1));
      final firstRequest = adapter.requests.single;
      expect(firstRequest.method, 'GET');
      expect(firstRequest.uri.origin, AppConstants.apiBaseUrl);
      expect(firstRequest.uri.path, '/todos');
      expect(firstRequest.queryParameters, {'limit': 20, 'skip': 0});
      expect(suggestions.state.items, hasLength(20));
      expect(suggestions.state.hasMore, isTrue);
      expect(find.text('  API task 1  '), findsOneWidget);
      final createdAfter = DateTime.now();
      await _tap(tester, _add(1));
      await _finish(
        tester,
        () =>
            suggestions.state.importedIds.contains(1) &&
            suggestions.state.importingIds.isEmpty,
      );
      expect(find.text(AppStrings.taskImported), findsOneWidget);
      expect(tester.widget<AppButton>(_add(1)).label, AppStrings.added);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: _add(1), matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      expect(tasks.state.status, TaskStatus.success);
      final imported = tasks.state.tasks.single;
      expect(imported.id, 'suggested-1');
      expect(imported.title, 'API task 1');
      expect(imported.priority, TaskPriority.medium);
      expect(imported.source, TaskSource.imported);
      expect(imported.isDone, isTrue);
      expect(imported.description, isEmpty);
      expect(imported.dueDate, isNull);
      expect(imported.createdAt.isBefore(createdAfter), isFalse);
      expect(imported.createdAt.isAfter(DateTime.now()), isFalse);
      expect(imported.updatedAt, imported.createdAt);
      expect(local.writes, 1);
      expect(local.records.keys, ['suggested-1']);
      expect(await TaskRepository(local).getById(imported.id), imported);

      await _tap(tester, _tab(AppStrings.myTasks));
      await tester.pumpAndSettle();
      final taskCard = find.byWidgetPredicate(
        (widget) => widget is TaskCard && widget.task.id == imported.id,
      );
      expect(taskCard, findsOneWidget);
      expect(tester.widget<TaskCard>(taskCard).task, imported);
      expect(find.text(AppStrings.taskImported), findsNothing);
      expect(find.text(AppStrings.noTasksTitle), findsNothing);
      await _tap(tester, _tab(AppStrings.suggested));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(1));
      expect(tester.widget<AppButton>(_add(1)).onPressed, isNull);
      expect(local.writes, 1);
      expect(tasks.state.tasks, [imported]);

      for (var drag = 0; drag < 14 && adapter.requests.length < 2; drag++) {
        await tester.drag(_suggestedList(), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _finish(tester, () => suggestions.state.items.length == 23);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.queryParameters, {'limit': 20, 'skip': 20});
      expect(suggestions.state.items.map((item) => item.id), [
        for (var id = 1; id <= 23; id++) id,
      ]);
      expect(suggestions.state.hasMore, isFalse);
      expect(suggestions.state.isLoadingMore, isFalse);
      for (var drag = 0; drag < 3; drag++) {
        await tester.drag(_suggestedList(), const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      expect(find.text('API task 23'), findsOneWidget);
      expect(adapter.requests, hasLength(2));
      expect(local.writes, 1);
      expect(await TaskRepository(local).getTasks(), [imported]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline and malformed API responses retry safely before importing',
    (tester) async {
      var attempt = 0;
      final adapter = _Adapter((request) {
        attempt++;
        if (attempt == 1) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
            error: 'private-transport-detail',
          );
        }
        if (attempt == 2) {
          return _response({
            'todos': [
              {
                'id': 1,
                'todo': 'private-invalid-payload',
                'completed': 'invalid',
                'userId': 7,
              },
            ],
            'total': 1,
            'skip': 0,
            'limit': 1,
          });
        }
        return _response(_page(total: 1));
      });
      final (tasks, suggestions, local) = await _pumpHome(tester, adapter);
      await _tap(tester, _tab(AppStrings.suggested));
      await _finish(
        tester,
        () => suggestions.state.status == SuggestedStatus.failure,
      );
      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text(AppStrings.networkError), findsOneWidget);
      expect(find.textContaining('private-transport-detail'), findsNothing);
      expect(tasks.state.tasks, isEmpty);
      expect(local.records, isEmpty);
      final retry = find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == AppStrings.retry,
      );
      await _tap(tester, retry);
      await _finish(
        tester,
        () =>
            attempt == 2 && suggestions.state.status == SuggestedStatus.failure,
      );
      expect(find.text(AppStrings.invalidResponse), findsOneWidget);
      expect(find.textContaining('private-invalid-payload'), findsNothing);
      expect(local.writes, 0);
      expect(suggestions.state.items, isEmpty);
      await _tap(tester, retry);
      await _finish(
        tester,
        () => suggestions.state.status == SuggestedStatus.success,
      );
      expect(adapter.requests, hasLength(3));
      for (final request in adapter.requests) {
        expect(request.queryParameters, {'limit': 20, 'skip': 0});
      }
      expect(find.byType(ErrorView), findsNothing);
      expect(suggestions.state.items, hasLength(1));
      expect(suggestions.state.hasMore, isFalse);
      await _tap(tester, _add(1));
      await _finish(tester, () => suggestions.state.importedIds.contains(1));
      expect(find.text(AppStrings.taskImported), findsOneWidget);
      expect(local.writes, 1);
      await _tap(tester, _tab(AppStrings.myTasks));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TaskCard, 'API task 1'), findsOneWidget);
      expect(tasks.state.tasks.single.id, 'suggested-1');
      expect(tasks.state.tasks.single.source, TaskSource.imported);
      expect(tester.takeException(), isNull);
    },
  );
}
