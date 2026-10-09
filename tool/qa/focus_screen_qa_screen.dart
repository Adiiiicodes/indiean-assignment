// Development-only entry to the real Focus screen, Cubits and persisted stores.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/focus/cubit/timer_cubit.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';

class FocusScreenQaScreen extends StatefulWidget {
  const FocusScreenQaScreen({super.key});

  @override
  State<FocusScreenQaScreen> createState() => _FocusScreenQaScreenState();
}

class _FocusScreenQaScreenState extends State<FocusScreenQaScreen> {
  static const _taskId = 'native-focus-screen-task';
  bool _busy = false;
  String _report =
      'Open the actual Focus screen. The short route changes only '
      'its injected timer duration to 3 seconds. Read saved results after '
      'completion or after restarting the app.';

  Future<TaskCubit> _loadedTasks() async {
    final tasks = context.read<TaskCubit>();
    if (tasks.state.status == TaskStatus.loading) {
      await tasks.stream.firstWhere(
        (state) => state.status != TaskStatus.loading,
      );
    }
    await tasks.load();
    if (tasks.state.status != TaskStatus.success) {
      throw const StorageException();
    }
    return tasks;
  }

  TaskModel? _findTask(TaskCubit tasks) {
    for (final task in tasks.state.tasks) {
      if (task.id == _taskId) return task;
    }
    return null;
  }

  Future<TaskModel> _seedTask() async {
    final tasks = await _loadedTasks();
    var task = _findTask(tasks);
    if (task == null) {
      await tasks.add(
        TaskModel(
          id: _taskId,
          title: 'Prepare focus demo',
          description:
              'Real task used to verify countdown, music, completion '
              'and persisted Done/Pending choices.',
          priority: TaskPriority.high,
        ),
      );
      task = _findTask(tasks);
    }
    if (tasks.state.status != TaskStatus.success || task == null) {
      throw const StorageException();
    }
    return task;
  }

  Future<void> _open({required bool short}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final task = await _seedTask();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => FocusScreen(
            task: task,
            timerFactory: short
                ? (repository, minutes) => TimerCubit(
                    repository,
                    initialMinutes: minutes,
                    secondsForMinutes: (_) => 3,
                  )
                : null,
          ),
        ),
      );
      if (mounted) await _readResults();
    } catch (error) {
      if (mounted) {
        setState(() => _report = 'ERROR: ${mapException(error).message}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readResults() async {
    final repository = context.read<FocusRepository>();
    final tasks = await _loadedTasks();
    final sessions = await repository.getSessions();
    final records = sessions
        .where((session) => session.taskId == _taskId)
        .toList();
    final task = _findTask(tasks);
    if (!mounted) return;
    setState(() {
      _report =
          'Saved sessions: ${sessions.length}\n'
          'Demo sessions: ${records.length}\n'
          'Task ID: $_taskId\n'
          'Task exists: ${task != null}\n'
          'Task is Done: ${task?.isDone ?? false}'
          '${records.map((session) => '\n\nSession ID: ${session.id}\n'
              'Completed: ${session.completed}\n'
              'Actual seconds: ${session.actualSeconds}\n'
              'Planned minutes: ${session.plannedMinutes}').join()}';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _report = 'ERROR: ${mapException(error).message}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetTask() async {
    final tasks = context.read<TaskCubit>();
    final task = await _seedTask();
    if (!mounted) return;
    if (task.isDone) {
      await tasks.update(task.copyWith(isDone: false));
      if (tasks.state.status != TaskStatus.success ||
          _findTask(tasks)?.isDone != false) {
        throw const StorageException();
      }
    }
    if (mounted) await _readResults();
  }

  Future<void> _clearSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear QA focus sessions?'),
        content: const Text(
          'This clears focus history in this QA installation. '
          'Tasks, accounts and settings remain saved.',
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
    if (confirmed != true || !mounted) return;
    await context.read<FocusRepository>().clearAll();
    if (mounted) await _readResults();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QA Focus screen')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _busy ? null : () => _open(short: false),
              child: const Text('Open Focus production'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _open(short: true),
              child: const Text('Open Focus short 3 sec'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await Navigator.of(context).pushNamed(Routes.music);
                    }),
              child: const Text('Open shared Music'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_readResults),
              child: const Text('Read Focus screen results'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_resetTask),
              child: const Text('Reset demo task to pending'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_clearSessions),
              child: const Text('Clear QA focus sessions'),
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(_report),
          ],
        ),
      ),
    ),
  );
}
