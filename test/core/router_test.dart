import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/video_repository.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/auth/view/signup_screen.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_state.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/settings_state.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:focusdesk/features/tasks/view/task_form_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';
import 'package:focusdesk/features/video/view/video_player_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/app_dependencies.dart';

class _FrozenAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _FrozenTaskCubit extends MockCubit<TaskState> implements TaskCubit {}

class _FrozenAudioCubit extends MockCubit<AudioState> implements AudioCubit {}

class _FrozenProfileCubit extends MockCubit<ProfileState>
    implements ProfileCubit {}

class _FrozenThemeCubit extends MockCubit<ThemeState> implements ThemeCubit {}

class _FrozenSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

Widget _host(GlobalKey<NavigatorState> navigatorKey, {TaskModel? task}) {
  final auth = _FrozenAuthCubit();
  when(() => auth.state).thenReturn(const AuthInitial());
  when(() => auth.checkSession()).thenAnswer((_) => Completer<void>().future);
  final tasks = _FrozenTaskCubit();
  when(() => tasks.state).thenReturn(
    TaskState(status: TaskStatus.success, tasks: task == null ? [] : [task]),
  );
  addTearDown(auth.close);
  addTearDown(tasks.close);
  final audio = _FrozenAudioCubit();
  when(() => audio.state).thenReturn(
    AudioState(
      status: AppPlayerStatus.paused,
      tracks: const AudioRepository().focusTracks,
      duration: const Duration(minutes: 3),
    ),
  );
  when(() => audio.init()).thenAnswer((_) async {});
  addTearDown(audio.close);
  final profile = _FrozenProfileCubit();
  when(() => profile.state).thenReturn(const ProfileState());
  final theme = _FrozenThemeCubit();
  when(() => theme.state).thenReturn(const ThemeState());
  final settings = _FrozenSettingsCubit();
  when(() => settings.state).thenReturn(const SettingsState());
  addTearDown(profile.close);
  addTearDown(theme.close);
  addTearDown(settings.close);
  return MultiBlocProvider(
    providers: [
      BlocProvider<AuthCubit>.value(value: auth),
      BlocProvider<TaskCubit>.value(value: tasks),
      BlocProvider<AudioCubit>.value(value: audio),
      BlocProvider<ProfileCubit>.value(value: profile),
      BlocProvider<ThemeCubit>.value(value: theme),
      BlocProvider<SettingsCubit>.value(value: settings),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      initialRoute: Routes.splash,
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
}

void main() {
  testWidgets('named routes preserve settings and return to splash on pop', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final task = TaskModel(id: 'id-42', title: 'Routing task');
    final destinations = <(String, Type, Object?)>[
      (Routes.login, LoginScreen, null),
      (Routes.signup, SignupScreen, null),
      (Routes.home, HomeScreen, null),
      (Routes.taskDetails, TaskDetailsScreen, 'id-42'),
      (Routes.taskForm, TaskFormScreen, task),
      (Routes.music, MusicScreen, null),
      (Routes.video, VideoScreen, null),
      (Routes.profile, ProfileScreen, null),
      (Routes.focus, FocusScreen, task),
    ];
    await tester.pumpWidget(_host(navigatorKey, task: task));
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(SplashScreen)))!.settings.name,
      Routes.splash,
    );

    for (final (name, screenType, argument) in destinations) {
      navigatorKey.currentState!.pushNamed(name, arguments: argument);
      await tester.pumpAndSettle();

      final screen = find.byType(screenType);
      expect(screen, findsOneWidget, reason: name);
      final settings = ModalRoute.of(tester.element(screen))!.settings;
      expect(settings.name, name);
      expect(settings.arguments, same(argument));
      if (name == Routes.taskDetails) {
        expect(tester.widget<TaskDetailsScreen>(screen).taskId, 'id-42');
        expect(find.text(task.title), findsOneWidget);
      } else if (name == Routes.taskForm) {
        expect(tester.widget<TaskFormScreen>(screen).task, same(task));
      } else if (name == Routes.focus) {
        expect(tester.widget<FocusScreen>(screen).task, same(task));
      }

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsOneWidget, reason: name);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown route returns home and clears the previous stack', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(navigatorKey));
    navigatorKey.currentState!.pushNamed(Routes.login);
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushNamed('/missing-page');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.notFoundTitle), findsWidgets);
    await tester.tap(find.text(AppStrings.returnHome));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(
      ModalRoute.of(tester.element(find.byType(HomeScreen)))!.settings.name,
      Routes.home,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid task details argument uses the friendly fallback', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(navigatorKey));
    navigatorKey.currentState!.pushNamed(Routes.taskDetails, arguments: 42);
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailsScreen), findsNothing);
    expect(find.text(AppStrings.notFoundTitle), findsWidgets);
    expect(find.text(AppStrings.returnHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid task form argument uses the friendly fallback', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(navigatorKey));
    navigatorKey.currentState!.pushNamed(Routes.taskForm, arguments: 'invalid');
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormScreen), findsNothing);
    expect(find.text(AppStrings.notFoundTitle), findsWidgets);
    expect(find.text(AppStrings.returnHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('typed video player route preserves its model and settings', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final video = const VideoRepository().videos.first;
    final settings = RouteSettings(name: Routes.videoPlayer, arguments: video);
    final route =
        AppRouter.onGenerateRoute(settings) as PageRouteBuilder<dynamic>;
    // Inspect the page without mounting the network player plugin.
    final page = route.buildPage(
      tester.element(find.byType(SizedBox)),
      const AlwaysStoppedAnimation<double>(1),
      const AlwaysStoppedAnimation<double>(0),
    );
    expect(page, isA<VideoPlayerScreen>());
    expect((page as VideoPlayerScreen).video, same(video));
    expect(route.settings, same(settings));
    expect(route.settings.name, Routes.videoPlayer);
    expect(route.settings.arguments, same(video));
    expect(tester.takeException(), isNull);
  });

  for (final argument in <Object?>[null, 'invalid', 42]) {
    testWidgets('video player argument $argument uses the friendly fallback', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_host(navigatorKey));
      navigatorKey.currentState!.pushNamed(
        Routes.videoPlayer,
        arguments: argument,
      );
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(find.text(AppStrings.notFoundTitle), findsWidgets);
      expect(find.text(AppStrings.returnHome), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('FocusDeskApp starts at splash and wires named navigation', (
    tester,
  ) async {
    final dependencies = await createTestDependencies();
    await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));

    final splash = find.byType(SplashScreen);
    expect(splash, findsOneWidget);
    final auth = tester.element(splash).read<AuthCubit>();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    final login = find.byType(LoginScreen);
    expect(login, findsOneWidget);
    expect(auth.state, const Unauthenticated());
    expect(tester.element(login).read<AuthCubit>(), same(auth));
    final tasks = tester.element(login).read<TaskCubit>();
    final loaded = tasks.load();
    await tester.pump();
    await loaded;
    expect(tasks.state.status, TaskStatus.failure);
    Navigator.of(tester.element(login)).pushNamed(Routes.home);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      tester.element(find.byType(HomeScreen)).read<AuthCubit>(),
      same(auth),
    );
    expect(tester.takeException(), isNull);
  });
}
