import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';

/// Development-only probe that exercises the same persisted repository as UI.
class FocusRepositoryQaScreen extends StatefulWidget {
  const FocusRepositoryQaScreen({super.key});

  @override
  State<FocusRepositoryQaScreen> createState() =>
      _FocusRepositoryQaScreenState();
}

class _FocusRepositoryQaScreenState extends State<FocusRepositoryQaScreen> {
  String? _busy;
  String _report =
      'Add a focus sample, then cold restart and read saved sessions.';

  Future<void> _run(
    String label,
    Future<String> Function(FocusRepository repository) operation,
  ) async {
    if (_busy != null) return;
    final repository = context.read<FocusRepository>();
    setState(() => _busy = label);
    try {
      final result = await operation(repository);
      final sessions = await repository.getSessions();
      final today = await repository.sessionsForDay(DateTime.now());
      final stats = await repository.todayStats();
      final seconds = today.fold<int>(
        0,
        (sum, session) => sum + session.actualSeconds,
      );
      if (stats.sessionsToday != today.length ||
          stats.focusMinutesToday != seconds ~/ 60) {
        throw const StorageException();
      }
      if (!mounted) return;
      setState(() {
        _report =
            'PASS: $result\n'
            'Saved count: ${sessions.length}\n'
            'Sessions today: ${stats.sessionsToday}\n'
            'Focus minutes today: ${stats.focusMinutesToday}\n'
            'Tasks completed today: ${stats.tasksCompletedToday}\n'
            'Current streak days: ${stats.currentStreakDays}'
            '${sessions.isEmpty ? '\nNo saved sessions.' : ''}'
            '${sessions.map(_details).join()}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _report = 'ERROR: ${mapException(error).message}');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _details(FocusSessionModel session) =>
      '\n\nID: ${session.id}\n'
      'Task: ${session.taskTitle}\n'
      'Task ID: ${session.taskId}\n'
      'Planned minutes: ${session.plannedMinutes}\n'
      'Actual seconds: ${session.actualSeconds}\n'
      'Completed: ${session.completed}\n'
      'Started: ${session.startedAt.toIso8601String()}\n'
      'Ended: ${session.endedAt.toIso8601String()}';

  Future<String> _add(FocusRepository repository) async {
    final before = await repository.getSessions();
    final now = DateTime.now();
    final sample = FocusSessionModel(
      taskId: 'native-focus-probe-task',
      taskTitle: 'Native focus sample',
      plannedMinutes: 25,
      actualSeconds: 120,
      completed: true,
      startedAt: now.subtract(const Duration(seconds: 120)),
      endedAt: now,
    );
    final added = await repository.addSession(sample);
    final saved = await repository.getSessions();
    if (added != sample ||
        saved.length != before.length + 1 ||
        saved.where((session) => session == sample).length != 1) {
      throw const StorageException();
    }
    return 'Focus sample persisted and read back exactly';
  }

  Future<void> _confirmClear() async {
    if (_busy != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear focus samples?'),
        content: const Text(
          'This clears saved focus sessions. Tasks, account and settings stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy != null) return;
    await _run('Clear focus samples', (repository) async {
      await repository.clearAll();
      if ((await repository.getSessions()).isNotEmpty) {
        throw const StorageException();
      }
      return 'Focus sessions cleared';
    });
  }

  Widget _button(String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppButton(
      label: label,
      onPressed: _busy == null ? action : null,
      isLoading: _busy == label,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Focus repository QA')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _button(
              'Add focus sample',
              () => unawaited(_run('Add focus sample', _add)),
            ),
            _button(
              'Read saved sessions',
              () => unawaited(
                _run(
                  'Read saved sessions',
                  (_) async => 'Saved sessions loaded from the repository',
                ),
              ),
            ),
            _button('Clear focus samples', () => unawaited(_confirmClear())),
            const SizedBox(height: 4),
            SelectableText(
              _report,
              key: const ValueKey('focus-repository-report'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
