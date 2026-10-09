import 'package:flutter/material.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';

class RouterQaScreen extends StatefulWidget {
  const RouterQaScreen({super.key});

  @override
  State<RouterQaScreen> createState() => _RouterQaScreenState();
}

class _RouterQaScreenState extends State<RouterQaScreen> {
  static const _routes = [
    Routes.splash,
    Routes.login,
    Routes.signup,
    Routes.home,
    Routes.taskDetails,
    Routes.taskForm,
    Routes.music,
    Routes.video,
    Routes.profile,
    Routes.focus,
    '/unknown',
  ];
  int _index = 0;

  Future<void> _open() async {
    final route = _routes[_index];
    await Navigator.of(context).pushNamed(
      route,
      arguments: switch (route) {
        Routes.taskDetails => 'native-task-42',
        Routes.taskForm => TaskModel(
          id: 'native-task-42',
          title: 'Routing task',
        ),
        Routes.focus => const {'id': 'native-task-42'},
        _ => null,
      },
    );
    if (mounted) setState(() => _index = (_index + 1) % _routes.length);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Named routing QA')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Route ${_index + 1} of ${_routes.length}'),
            const SizedBox(height: 16),
            AppButton(
              label: 'Open next route: ${_routes[_index]}',
              onPressed: _open,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Open unknown route',
              onPressed: () => Navigator.of(context).pushNamed('/unknown'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Open each real named route, inspect it, and use Back to continue. Unknown route also offers Return home.',
            ),
          ],
        ),
      ),
    ),
  );
}
