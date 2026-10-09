import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
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
      ],
      child: BlocProvider<AuthCubit>(
        create: (_) => AuthCubit(dependencies.auth),
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
    );
  }
}
