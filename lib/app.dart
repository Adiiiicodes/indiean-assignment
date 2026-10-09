import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';

class FocusDeskApp extends StatelessWidget {
  const FocusDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: AppTheme.systemUiBuilder,
      home: const Scaffold(
        body: SafeArea(child: Center(child: Text(AppStrings.appName))),
      ),
    );
  }
}
