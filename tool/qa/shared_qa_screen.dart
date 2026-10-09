import 'package:flutter/material.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:focusdesk/shared/widgets/priority_chip.dart';
import 'package:focusdesk/shared/widgets/section_header.dart';

class SharedQaScreen extends StatefulWidget {
  const SharedQaScreen({super.key});

  @override
  State<SharedQaScreen> createState() => _SharedQaScreenState();
}

class _SharedQaScreenState extends State<SharedQaScreen> {
  final _password = TextEditingController(text: 'Focus@123');
  int _actions = 0;
  int _retries = 0;
  int _undos = 0;
  int _state = 0;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Shared widgets QA'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Controls'),
            Tab(text: 'States'),
            Tab(text: 'Snackbars'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Reusable controls'),
                  const SizedBox(height: 16),
                  Text('Actions: $_actions'),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Perform action',
                    icon: Icons.check,
                    onPressed: () => setState(() => _actions++),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Loading action',
                    isLoading: true,
                    onPressed: () => setState(() => _actions += 100),
                  ),
                  const SizedBox(height: 20),
                  AppTextField(
                    label: 'Password',
                    controller: _password,
                    isPassword: true,
                    prefixIcon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 20),
                  const Wrap(
                    spacing: 8,
                    children: [
                      PriorityChip(priority: 'high'),
                      PriorityChip(priority: 'medium'),
                      PriorityChip(priority: 'low'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (var index = 0; index < 3; index++)
                        ChoiceChip(
                          label: Text(['Empty', 'Error', 'Loading'][index]),
                          selected: _state == index,
                          onSelected: (_) => setState(() => _state = index),
                        ),
                    ],
                  ),
                ),
                Text('Actions: $_actions · Retries: $_retries'),
                Expanded(
                  child: switch (_state) {
                    0 => EmptyView(
                      icon: Icons.task_alt,
                      title: 'A fresh start',
                      message: 'Your next task can start here.',
                      actionLabel: 'Create task',
                      onAction: () => setState(() => _actions++),
                    ),
                    1 => ErrorView(
                      message: 'A temporary connection problem.',
                      onRetry: () => setState(() => _retries++),
                    ),
                    _ => const LoadingView(
                      message: 'Preparing your workspace…',
                    ),
                  },
                ),
              ],
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Undo actions: $_undos'),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Show success',
                    onPressed: () =>
                        AppSnackbar.showSuccess(context, 'Saved successfully.'),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Show error',
                    onPressed: () =>
                        AppSnackbar.showError(context, 'Please try again.'),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Show undo',
                    onPressed: () => AppSnackbar.showUndo(
                      context,
                      'Task deleted.',
                      () => setState(() => _undos++),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
