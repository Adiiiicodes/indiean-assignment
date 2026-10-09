import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class TaskDetailsScreen extends StatelessWidget {
  const TaskDetailsScreen({super.key, this.taskId});

  final String? taskId;

  @override
  Widget build(BuildContext context) {
    const title = AppStrings.taskDetails;
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
