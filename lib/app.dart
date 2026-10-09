import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:focusdesk/core/router/routes.dart';

class FocusDeskApp extends StatelessWidget {
  const FocusDeskApp({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDependencies>.value(value: dependencies),
        RepositoryProvider<PrefsService>.value(value: dependencies.prefs),
        RepositoryProvider<HiveService>.value(value: dependencies.hive),
        RepositoryProvider<AuthRepository>.value(value: dependencies.auth),
        RepositoryProvider<TaskRepository>.value(value: dependencies.tasks),
        RepositoryProvider<AudioRepository>.value(value: dependencies.audio),
        RepositoryProvider<Dio>.value(value: dependencies.dio),
        RepositoryProvider<SuggestedRepository>.value(
          value: dependencies.suggested,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>(create: (_) => AuthCubit(dependencies.auth)),
          BlocProvider<TaskCubit>(create: (_) => TaskCubit(dependencies.tasks)),
          BlocProvider<AudioCubit>(
            create: (_) => AudioCubit(
              dependencies.audio,
              dependencies.audioPlayerFactory(),
            ),
          ),
          BlocProvider<SuggestedCubit>(
            create: (context) => SuggestedCubit(
              dependencies.suggested,
              context.read<TaskCubit>(),
            ),
          ),
        ],
        child: _TaskSessionBinding(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: AppStrings.appName,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            builder: AppTheme.systemUiBuilder,
            initialRoute: Routes.splash,
            onGenerateRoute: AppRouter.onGenerateRoute,
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
      final tasks = context.read<TaskCubit>();
      tasks.reset();
      context.read<SuggestedCubit>().reset();
      unawaited(tasks.load());
    } else if (state is Unauthenticated) {
      _userId = null;
      context.read<TaskCubit>().reset();
      context.read<SuggestedCubit>().reset();
    }
  }

  @override
  Widget build(BuildContext context) => BlocListener<AuthCubit, AuthState>(
    listener: (_, state) => _syncSession(state),
    child: widget.child,
  );
}
