import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/data/repositories/video_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/cubit/timer_cubit.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:focusdesk/features/tasks/view/task_form_screen.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';
import 'package:focusdesk/features/video/widgets/video_card.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_audio_player_service.dart';

class _MemoryHive extends HiveService {
  final boxes = <String, Map<String, String>>{};
  int sessionWrites = 0;

  @override
  List<String> readAll(String box) => boxes[box]?.values.toList() ?? [];
  @override
  String? read(String box, String key) => boxes[box]?[key];
  @override
  Future<void> put(String box, String key, String value) async {
    (boxes[box] ??= {})[key] = value;
    if (box == AppConstants.focusSessionsBox) sessionWrites++;
  }

  @override
  Future<void> delete(String box, String key) async => boxes[box]?.remove(key);
  @override
  Future<void> clear(String box) async => boxes[box]?.clear();
}

class _UnusedNetwork implements HttpClientAdapter {
  int requests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw StateError('This journey must keep Suggested requests lazy.');
  }

  @override
  void close({bool force = false}) {}
}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  int _ticks = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _ticks;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _ticks++;
    callback();
  }
}

class _Clock {
  _Clock() {
    final today = DateTime.now();
    current = DateTime(today.year, today.month, today.day, 12);
  }
  late DateTime current;
  _ManualTimer? timer;
  DateTime now() => current;
  Timer periodic(Duration interval, void Function() tick) =>
      timer = _ManualTimer(tick);
  void advance(int seconds) {
    current = current.add(Duration(seconds: seconds));
    timer?.fire();
  }
}

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == label,
);
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
);
Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
Finder _dialog(String label) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(label));

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find
          .descendant(
            of: find.byType(TasksTab),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await _frames(tester);
  }
  if (finder.hitTestable().evaluate().isEmpty &&
      find.byType(SnackBar).hitTestable().evaluate().isNotEmpty) {
    await tester.drag(
      find.byType(SnackBar).hitTestable(),
      const Offset(0, 150),
    );
    await _frames(tester);
  }
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await _frames(tester);
}

void _expectRoute(WidgetTester tester, Type screen, String name) {
  final finder = find.byType(screen);
  expect(finder, findsOneWidget);
  expect(ModalRoute.of(tester.element(finder))!.settings.name, name);
}

void main() {
  testWidgets('real app completes the task, focus, media and logout journey', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final prefs = PrefsService(preferences);
    final hive = _MemoryHive();
    final clock = _Clock();
    final tasks = TaskRepository(TaskLocalDatasource(hive), now: clock.now);
    final focus = FocusRepository(
      FocusLocalDatasource(hive),
      tasks,
      now: clock.now,
    );
    final service = FakeAudioPlayerService();
    final network = _UnusedNetwork();
    final dio = Dio()..httpClientAdapter = network;
    final dependencies = AppDependencies(
      prefs: prefs,
      hive: hive,
      auth: AuthRepository(AuthLocalDatasource(prefs), delay: Duration.zero),
      tasks: tasks,
      focus: focus,
      dio: dio,
      audioPlayerFactory: () => service,
    );
    addTearDown(() => dio.close(force: true));
    late TimerCubit timer;
    var timerCreations = 0;
    await tester.pumpWidget(
      FocusDeskApp(
        dependencies: dependencies,
        focusTimerFactory: (repository, minutes) {
          expect(repository, same(focus));
          expect(minutes, AppConstants.defaultFocusMinutes);
          timerCreations++;
          return timer = TimerCubit(
            repository,
            initialMinutes: minutes,
            now: clock.now,
            periodicTicker: clock.periodic,
            secondsForMinutes: (_) => 3,
          );
        },
      ),
    );
    _expectRoute(tester, SplashScreen, Routes.splash);
    final auth = tester.element(find.byType(SplashScreen)).read<AuthCubit>();
    await tester.pump(AppConstants.splashDuration);
    await _frames(tester);
    _expectRoute(tester, LoginScreen, Routes.login);
    expect(auth.state, const Unauthenticated());
    expect(timerCreations, 0);
    await _tap(tester, find.byKey(const ValueKey('login-demo-account')));
    expect(
      tester.widget<AppTextField>(_field(AppStrings.email)).controller!.text,
      AppConstants.demoEmail,
    );
    await _tap(tester, _button(AppStrings.login));
    _expectRoute(tester, HomeScreen, Routes.home);
    final context = tester.element(find.byType(TasksTab));
    final taskCubit = context.read<TaskCubit>();
    final stats = context.read<StatsCubit>();
    final suggested = context.read<SuggestedCubit>();
    expect(context.read<AuthCubit>(), same(auth));
    expect(auth.state, isA<Authenticated>());
    expect(preferences.getString(AppConstants.sessionUserKey), 'demo-user');
    expect(taskCubit.state.tasks, isEmpty);

    await _tap(tester, find.byType(FloatingActionButton));
    _expectRoute(tester, TaskFormScreen, Routes.taskForm);
    for (final (label, value) in [
      (AppStrings.title, 'Finish the app smoke test'),
      (AppStrings.description, 'One complete production journey.'),
    ]) {
      await tester.ensureVisible(_field(label));
      await tester.enterText(_field(label), value);
      await _frames(tester);
    }
    await _tap(tester, _button(AppStrings.save));
    _expectRoute(tester, HomeScreen, Routes.home);
    final saved = (await tasks.getTasks()).single;
    expect(saved.title, 'Finish the app smoke test');
    expect(saved.description, 'One complete production journey.');
    expect(saved.isDone, isFalse);
    await _tap(tester, find.widgetWithText(TaskCard, saved.title));
    _expectRoute(tester, TaskDetailsScreen, Routes.taskDetails);
    expect(
      ModalRoute.of(tester.element(find.byType(TaskDetailsScreen)))!
          .settings
          .arguments,
      saved.id,
    );
    await _tap(tester, _button(AppStrings.startFocus));
    _expectRoute(tester, FocusScreen, Routes.focus);
    expect(tester.widget<FocusScreen>(find.byType(FocusScreen)).task, saved);
    expect(timerCreations, 1);
    final audio = tester.element(find.byType(FocusScreen)).read<AudioCubit>();
    await _tap(tester, find.byKey(const ValueKey('focus-start')));
    expect(timer.state.status, TimerStatus.running);
    expect(audio.state.status, AppPlayerStatus.playing);
    clock.advance(3);
    await _frames(tester);
    await _frames(tester);
    expect(find.text(AppStrings.greatFocus), findsOneWidget);
    expect(timer.state.lastSession, isNotNull);
    await _tap(tester, _dialog(AppStrings.yes));
    final session = (await focus.getSessions()).single;
    expect(session.taskId, saved.id);
    expect(session.taskTitle, saved.title);
    expect(session.plannedMinutes, 25);
    expect(session.actualSeconds, 3);
    expect(session.completed, isTrue);
    expect(hive.sessionWrites, 1);
    expect((await tasks.getById(saved.id))!.isDone, isTrue);
    expect(
      stats.state.stats,
      const FocusStats(
        sessionsToday: 1,
        tasksCompletedToday: 1,
        currentStreakDays: 1,
      ),
    );
    await tester.pageBack();
    await _frames(tester);
    await _frames(tester);
    _expectRoute(tester, TaskDetailsScreen, Routes.taskDetails);
    expect(timer.isClosed, isTrue);
    expect(clock.timer!.isActive, isFalse);
    expect(audio.isClosed, isFalse);
    expect(service.disposed, isFalse);
    await tester.pageBack();
    await _frames(tester);
    _expectRoute(tester, HomeScreen, Routes.home);

    await _tap(tester, _tab(AppStrings.music));
    expect(find.byType(MusicScreen), findsOneWidget);
    expect(
      tester.element(find.byType(MusicScreen)).read<AudioCubit>(),
      same(audio),
    );
    expect(audio.state.tracks, hasLength(3));
    expect(service.playlistLoads, hasLength(1));
    await _tap(tester, find.byKey(const ValueKey('audio-play-pause')));
    expect(audio.state.status, AppPlayerStatus.playing);
    await _tap(tester, find.byKey(const ValueKey('audio-play-pause')));
    expect(audio.state.status, AppPlayerStatus.paused);
    await _tap(tester, _tab(AppStrings.videos));
    expect(find.byType(VideoScreen), findsOneWidget);
    expect(find.byType(VideoCard), findsNWidgets(2));
    for (final video in const VideoRepository().videos) {
      expect(find.text(video.title), findsOneWidget);
    }

    await _tap(tester, _tab(AppStrings.profile));
    expect(find.byType(ProfileScreen), findsOneWidget);
    final dark = find.descendant(
      of: find.byKey(const ValueKey('profile-theme')),
      matching: find.text(AppStrings.darkTheme),
    );
    await _tap(tester, dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      preferences.getString(AppConstants.themeModeKey),
      ThemeMode.dark.name,
    );
    expect(
      tester.element(find.byType(ProfileScreen)).read<ThemeCubit>().state.mode,
      ThemeMode.dark,
    );
    final pausesBeforeLogout = service.calls('pause');
    await _tap(tester, find.byKey(const ValueKey('profile-logout')));
    expect(find.text(AppStrings.logoutTitle), findsOneWidget);
    await _tap(tester, _dialog(AppStrings.logout));
    await _frames(tester);
    _expectRoute(tester, LoginScreen, Routes.login);
    expect(
      Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
      isFalse,
    );
    expect(auth.state, const Unauthenticated());
    expect(preferences.getString(AppConstants.sessionUserKey), isNull);
    expect(taskCubit.state.tasks, isEmpty);
    expect(suggested.state.items, isEmpty);
    expect(stats.state.stats, const FocusStats());
    expect(service.calls('pause'), greaterThan(pausesBeforeLogout));
    expect(audio.state.position, Duration.zero);
    expect(audio.state.currentIndex, 0);
    expect(audio.state.status, AppPlayerStatus.paused);
    expect((await tasks.getTasks()).single.isDone, isTrue);
    expect(await focus.getSessions(), [session]);
    expect(network.requests, 0);
    expect(service.disposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    expect(auth.isClosed, isTrue);
    expect(taskCubit.isClosed, isTrue);
    expect(suggested.isClosed, isTrue);
    expect(stats.isClosed, isTrue);
    expect(audio.isClosed, isTrue);
    expect(service.disposed, isTrue);
    expect(service.calls('dispose'), 1);
    expect(service.hasListeners, isFalse);
  });
}
