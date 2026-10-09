import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key, this.task});

  final Object? task;

  @override
  Widget build(BuildContext context) {
    const title = AppStrings.focusSession;
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
