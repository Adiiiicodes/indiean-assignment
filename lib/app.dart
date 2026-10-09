import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';

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
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AppStrings.appName,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        builder: AppTheme.systemUiBuilder,
        home: const Scaffold(
          body: SafeArea(child: Center(child: Text(AppStrings.appName))),
        ),
      ),
    );
  }
}
