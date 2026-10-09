import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/widgets/audio_lifecycle_binding.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/data/repositories/profile_repository.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';

class FocusDeskApp extends StatelessWidget {
  const FocusDeskApp({
    required this.dependencies,
    this.focusTimerFactory,
    super.key,
  });
  final AppDependencies dependencies;
  final FocusTimerFactory? focusTimerFactory;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDependencies>.value(value: dependencies),
        RepositoryProvider<PrefsService>.value(value: dependencies.prefs),
        RepositoryProvider<HiveService>.value(value: dependencies.hive),
        RepositoryProvider<AuthRepository>.value(value: dependencies.auth),
        RepositoryProvider<ProfileRepository>.value(
          value: dependencies.profile,
        ),
        RepositoryProvider<TaskRepository>.value(value: dependencies.tasks),
        RepositoryProvider<FocusRepository>.value(value: dependencies.focus),
        RepositoryProvider<AudioRepository>.value(value: dependencies.audio),
        RepositoryProvider<Dio>.value(value: dependencies.dio),
        RepositoryProvider<SuggestedRepository>.value(
          value: dependencies.suggested,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(
            create: (_) => ThemeCubit(
              dependencies.prefs,
              initialMode: dependencies.initialThemeMode,
            ),
          ),
          BlocProvider<SettingsCubit>(
            create: (_) => SettingsCubit(
              dependencies.prefs,
              initialMinutes: dependencies.initialFocusMinutes,
            ),
          ),
          BlocProvider<AuthCubit>(create: (_) => AuthCubit(dependencies.auth)),
          BlocProvider<TaskCubit>(create: (_) => TaskCubit(dependencies.tasks)),
          BlocProvider<StatsCubit>(
            create: (_) => StatsCubit(dependencies.focus),
          ),
          BlocProvider<SuggestedCubit>(
            create: (context) => SuggestedCubit(
              dependencies.suggested,
              context.read<TaskCubit>(),
            ),
          ),
        ],
        child: AudioLifecycleBinding(
          repository: dependencies.audio,
          serviceFactory: dependencies.audioPlayerFactory,
          child: BlocProvider<ProfileCubit>(
            create: (context) => ProfileCubit(
              dependencies.profile,
              context.read<AuthCubit>(),
              stopAudio: () => AudioLifecycleBinding.stopIfCreated(context),
              refreshTasks: () async {
                final tasks = context.read<TaskCubit>();
                tasks.reset();
                context.read<SuggestedCubit>().reset();
                await tasks.load();
                if (tasks.state.status == TaskStatus.failure) {
                  throw const StorageException();
                }
              },
            ),
            child: _TaskSessionBinding(
              child: BlocBuilder<ThemeCubit, ThemeState>(
                buildWhen: (previous, current) => previous.mode != current.mode,
                builder: (context, state) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: AppStrings.appName,
                  theme: AppTheme.light,
                  darkTheme: AppTheme.dark,
                  themeMode: state.mode,
                  builder: AppTheme.systemUiBuilder,
                  initialRoute: Routes.splash,
                  onGenerateRoute: focusTimerFactory == null
                      ? AppRouter.onGenerateRoute
                      : (settings) => AppRouter.onGenerateRoute(
                          settings,
                          focusTimerFactory: focusTimerFactory,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskSessionBinding extends StatefulWidget {
  const _TaskSessionBinding({required this.child});
  final Widget child;

  @override
  State<_TaskSessionBinding> createState() => _TaskSessionBindingState();
}

class _TaskSessionBindingState extends State<_TaskSessionBinding> {
  String? _userId;

  @override
  void initState() {
    super.initState();
    _syncSession(context.read<AuthCubit>().state);
  }

  void _syncSession(AuthState state) {
    if (state is Authenticated && state.user.id != _userId) {
      _userId = state.user.id;
      context.read<StatsCubit>().reset();
      final tasks = context.read<TaskCubit>();
      tasks.reset();
      context.read<SuggestedCubit>().reset();
      unawaited(tasks.load());
    } else if (state is Unauthenticated) {
      _userId = null;
      context.read<StatsCubit>().reset();
      context.read<TaskCubit>().reset();
      context.read<SuggestedCubit>().reset();
    }
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<AuthCubit, AuthState>(
        listener: (_, state) => _syncSession(state),
      ),
      BlocListener<TaskCubit, TaskState>(
        listenWhen: (before, after) =>
            after.status == TaskStatus.success &&
            (before.status != TaskStatus.success ||
                !listEquals(before.tasks, after.tasks)),
        listener: (context, _) {
          if (context.read<AuthCubit>().state is Authenticated) {
            unawaited(context.read<StatsCubit>().refresh());
          }
        },
      ),
    ],
    child: widget.child,
  );
}
