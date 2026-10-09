import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/focus/cubit/timer_cubit.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';

/// Development-only real-clock timer and persisted-session probe.
class TimerQaScreen extends StatefulWidget {
  const TimerQaScreen({super.key});

  @override
  State<TimerQaScreen> createState() => _TimerQaScreenState();
}

class _TimerQaScreenState extends State<TimerQaScreen> {
  final _task = TaskModel(
    id: 'native-timer-probe-task',
    title: 'Native timer sample',
  );
  late FocusRepository _repository;
  TimerCubit? _timer;
  bool _short = false;
  bool _switching = false;
  String? _busy;
  String _report = 'Read sessions after finishing or after a cold restart.';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer == null) {
      _repository = context.read<FocusRepository>();
      _timer = _createTimer();
    }
  }

  TimerCubit _createTimer() => _short
      ? TimerCubit(_repository, secondsForMinutes: (_) => 3)
      : TimerCubit(_repository);

  @override
  void dispose() {
    unawaited(_timer?.close());
    super.dispose();
  }

  Future<void> _switchMode(bool short) async {
    if (_switching || _busy != null || short == _short) return;
    final timer = _timer!;
    if (timer.state.isSaving ||
        timer.state.hasUnsavedSession ||
        timer.state.status == TimerStatus.running ||
        timer.state.status == TimerStatus.paused) {
      return;
    }
    setState(() => _switching = true);
    await timer.close();
    if (!mounted) return;
    setState(() {
      _short = short;
      _timer = _createTimer();
      _switching = false;
    });
  }

  Future<void> _read({String prefix = 'Saved sessions read'}) async {
    if (_busy != null || _switching) return;
    setState(() => _busy = 'Read sessions');
    try {
      final sessions = await _repository.getSessions();
      final stats = await _repository.todayStats();
      if (!mounted) return;
      setState(() {
        _report =
            'PASS: $prefix\nSaved count: ${sessions.length}\n'
            'Today: ${stats.sessionsToday} sessions / '
            '${stats.focusMinutesToday} minutes / '
            '${stats.currentStreakDays} streak days'
            '${sessions.isEmpty ? '\nNo saved sessions.' : ''}'
            '${sessions.map((session) => '\n\n${session.taskTitle}\n'
                'ID: ${session.id}\n'
                'Planned: ${session.plannedMinutes} minutes\n'
                'Actual: ${session.actualSeconds} seconds\n'
                'Completed: ${session.completed}\n'
                'Started: ${session.startedAt.toIso8601String()}\n'
                'Ended: ${session.endedAt.toIso8601String()}').join()}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _report = 'ERROR: ${mapException(error).message}');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _save(bool retry) async {
    if (_busy != null || _switching) return;
    final timer = _timer!;
    setState(() => _busy = retry ? 'Retry save' : 'Finish early');
    try {
      final saved = await (retry ? timer.retrySave() : timer.finishEarly());
      if (!mounted) return;
      setState(() {
        _report = saved
            ? 'Timer finished. Read sessions to verify the persisted record.'
            : timer.state.errorMessage ?? 'No session saved. A partial session needs more than 10 seconds.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _report = 'ERROR: ${mapException(error).message}');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _clear() async {
    if (_busy != null || _switching) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear QA sessions?'),
        content: const Text('Clear saved focus sessions only?'),
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
    setState(() => _busy = 'Clear QA sessions');
    try {
      await _repository.clearAll();
      if (!mounted) return;
      setState(() => _busy = null);
      await _read(prefix: 'Focus sessions cleared');
    } catch (error) {
      if (mounted) {
        setState(() {
          _report = 'ERROR: ${mapException(error).message}';
          _busy = null;
        });
      }
    }
  }

  String _time(int seconds) =>
      '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
      '${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  Widget _action(String label, VoidCallback? action) => FilledButton.tonal(
    onPressed: action,
    child: _busy == label
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Timer QA')),
    body: SafeArea(
      child: BlocBuilder<TimerCubit, TimerState>(
        bloc: _timer!,
        builder: (context, state) {
          final blocked = _busy != null || _switching || state.isSaving;
          final active =
              state.status == TimerStatus.running ||
              state.status == TimerStatus.paused;
          final canConfigure = !blocked && !active && !state.hasUnsavedSession;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Production timer 25'),
                      selected: !_short,
                      onSelected: canConfigure
                          ? (_) => unawaited(_switchMode(false))
                          : null,
                    ),
                    ChoiceChip(
                      label: const Text('Short completion 3 sec'),
                      selected: _short,
                      onSelected: canConfigure
                          ? (_) => unawaited(_switchMode(true))
                          : null,
                    ),
                  ],
                ),
                Text(
                  _time(state.remainingSeconds),
                  key: const ValueKey('qa-timer-clock'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  'Status: ${state.status.name} / '
                  'Remaining: ${state.remainingSeconds} / Total: ${state.totalSeconds}',
                  textAlign: TextAlign.center,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final minutes in [15, 25, 45])
                      ChoiceChip(
                        label: Text('$minutes min'),
                        selected: state.selectedMinutes == minutes,
                        onSelected: canConfigure
                            ? (_) => _timer!.setDuration(minutes)
                            : null,
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _action(
                      'Start',
                      canConfigure ? () => _timer!.start(_task) : null,
                    ),
                    _action(
                      'Pause',
                      !blocked && state.status == TimerStatus.running
                          ? () => _timer!.pause()
                          : null,
                    ),
                    _action(
                      'Resume',
                      !blocked && state.status == TimerStatus.paused
                          ? () => _timer!.resume()
                          : null,
                    ),
                    _action(
                      'Reset',
                      !blocked && !state.hasUnsavedSession
                          ? () => _timer!.reset()
                          : null,
                    ),
                    _action(
                      'Finish early',
                      !blocked && active ? () => unawaited(_save(false)) : null,
                    ),
                    _action(
                      'Retry save',
                      !blocked && state.hasUnsavedSession
                          ? () => unawaited(_save(true))
                          : null,
                    ),
                  ],
                ),
                if (state.isSaving) const LinearProgressIndicator(),
                if (state.errorMessage != null)
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (state.lastSession case final session?)
                  Text(
                    'Saved: ${session.actualSeconds} seconds / '
                    'Completed: ${session.completed}',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _action(
                      'Read sessions',
                      !blocked ? () => unawaited(_read()) : null,
                    ),
                    _action(
                      'Clear QA sessions',
                      canConfigure ? () => unawaited(_clear()) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _report,
                  key: const ValueKey('qa-timer-sessions'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
