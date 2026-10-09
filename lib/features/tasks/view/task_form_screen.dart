import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class TaskFormScreen extends StatelessWidget {
  const TaskFormScreen({super.key, this.task});

  final Object? task;

  @override
  Widget build(BuildContext context) {
    final title = task == null ? AppStrings.newTask : AppStrings.editTask;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    );
  }
}
