import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const title = AppStrings.appName;
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: SafeArea(
        child: Center(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    );
  }
}
