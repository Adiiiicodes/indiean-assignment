import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';
import 'package:focusdesk/features/focus/cubit/timer_cubit.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/widgets/focus_completion_dialog.dart';
import 'package:focusdesk/features/focus/widgets/focus_countdown.dart';
import 'package:focusdesk/features/focus/widgets/focus_music_player.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';

typedef FocusTimerFactory = TimerCubit Function(
  FocusRepository repository,
  int initialMinutes,
);

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, this.task, this.timerFactory});

  final TaskModel? task;
  final FocusTimerFactory? timerFactory;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  TimerCubit? _timer;
  AudioCubit? _audio;
  BuildContext? _feedbackContext;
  Future<void> _musicQueue = Future.value();
  int _musicToken = 0;
  int _musicPending = 0;
  int _handledRevision = 0;
  int _statsRevision = 0;
  bool _musicWanted = false;
  bool _musicEnabled = true;
  bool _dialogOpen = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _disposing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer == null) {
      final repository = context.read<FocusRepository>();
      final minutes = context.read<SettingsCubit>().state.defaultFocusMinutes;
      _timer =
          widget.timerFactory?.call(repository, minutes) ??
          TimerCubit(repository, initialMinutes: minutes);
      if (widget.task != null) _audio = context.read<AudioCubit>();
    }
  }

  @override
  void dispose() {
    // Invalidate delayed playback before queuing a final shared-player pause.
    _disposing = true;
    unawaited(_requestMusic(false));
    unawaited(_timer?.close());
    super.dispose();
  }

  bool get _current =>
      mounted && !_disposing && (ModalRoute.of(context)?.isCurrent ?? true);

  void _error(String message) {
    final feedback = _feedbackContext;
    if (_current && feedback != null && feedback.mounted) {
      AppSnackbar.showError(feedback, message);
    }
  }

  Future<void> _waitForAudio(AudioCubit audio) async {
    if (audio.isClosed || !audio.state.isBusy) return;
    await audio.stream.firstWhere((state) => !state.isBusy);
  }

  Future<void> _requestMusic(bool play, {bool retry = false}) {
    _musicWanted = play;
    final token = ++_musicToken;
    final audio = _audio;
    if (audio == null || audio.isClosed) return Future.value();
    _musicPending++;
    if (mounted && !_disposing) setState(() {});
    final operation = _musicQueue.then<void>((_) async {
      try {
        if (play || retry) await (retry ? audio.retry() : audio.init());
        await _waitForAudio(audio);
        if (audio.isClosed) return;
        if (play &&
            mounted &&
            !_disposing &&
            _musicWanted &&
            token == _musicToken) {
          await audio.play();
          // A pause/reset/leave can arrive while the decoder accepts Play.
          if (!mounted || _disposing || !_musicWanted || token != _musicToken) {
            await _waitForAudio(audio);
            if (!audio.isClosed) await audio.pause();
          }
        } else if (!play && audio.state.tracks.isNotEmpty) {
          await audio.pause();
        }
      } catch (error) {
        if (mounted && !_disposing && token == _musicToken) {
          _error(mapException(error).message);
        }
      } finally {
        _musicPending--;
        if (mounted && !_disposing) setState(() {});
      }
    });
    _musicQueue = operation;
    return operation;
  }

  Future<void> _nextTrack() {
    final audio = _audio;
    if (_disposing || !mounted || audio == null || audio.isClosed) {
      return Future.value();
    }
    _musicPending++;
    setState(() {});
    final operation = _musicQueue.then<void>((_) async {
      try {
        await _waitForAudio(audio);
        if (mounted && !_disposing && !audio.isClosed) await audio.next();
      } catch (error) {
        _error(mapException(error).message);
      } finally {
        _musicPending--;
        if (mounted && !_disposing) setState(() {});
      }
    });
    _musicQueue = operation;
    return operation;
  }

  void _onTimer(TimerState state) {
    if (state.lastSession != null && state.revision > _statsRevision) {
      _statsRevision = state.revision;
      final stats = context.read<StatsCubit?>();
      if (stats != null) unawaited(stats.refresh());
    }
    if (state.status != TimerStatus.running && _musicWanted) {
      unawaited(_requestMusic(false));
    }
    unawaited(_completeIfReady(state));
  }

  Future<void> _completeIfReady(TimerState state) async {
    final session = state.lastSession;
    if (!_current ||
        _leaving ||
        _dialogOpen ||
        state.isSaving ||
        state.hasUnsavedSession ||
        session == null ||
        !session.completed ||
        state.revision <= _handledRevision) {
      return;
    }
    _handledRevision = state.revision;
    _dialogOpen = true;
    setState(() {});
    try {
      await _requestMusic(false);
      if (!mounted || !_current || _leaving) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            FocusCompletionDialog(onMarkDone: () => _markDone(session.taskId)),
      );
      final feedback = _feedbackContext;
      if (_current && feedback != null && feedback.mounted) {
        AppSnackbar.showSuccess(
          feedback,
          AppStrings.focusSummary(session.actualSeconds),
        );
      }
    } finally {
      _dialogOpen = false;
      if (mounted && !_disposing) setState(() {});
    }
  }

  Future<String?> _markDone(String id) async {
    final tasks = context.read<TaskCubit>();
    if (tasks.state.status == TaskStatus.loading) {
      return AppStrings.storageError;
    }
    if (tasks.state.status == TaskStatus.initial ||
        tasks.state.status == TaskStatus.failure) {
      await tasks.load();
    }
    if (!mounted || _disposing) return AppStrings.storageError;
    if (tasks.state.status != TaskStatus.success) {
      return tasks.state.errorMessage ?? AppStrings.storageError;
    }
    final matching = tasks.state.tasks.where((task) => task.id == id);
    if (matching.isEmpty) return AppStrings.taskNotFound;
    if (matching.first.isDone) return null;
    await tasks.toggleDone(id);
    if (!mounted || _disposing) return AppStrings.storageError;
    return tasks.state.status == TaskStatus.success &&
            tasks.state.tasks.any((task) => task.id == id && task.isDone)
        ? null
        : tasks.state.errorMessage ?? AppStrings.storageError;
  }

  Future<bool> _confirm(String title, String message, String action) async {
    if (_dialogOpen) return false;
    _dialogOpen = true;
    setState(() {});
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    action == AppStrings.leave
                        ? AppStrings.stay
                        : AppStrings.cancel,
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _dialogOpen = false;
      if (mounted && !_disposing) setState(() {});
    }
  }

  void _start() {
    final task = widget.task;
    if (task == null || _dialogOpen || _leaving) return;
    if (_timer!.start(task) && _musicEnabled) unawaited(_requestMusic(true));
  }

  void _pause() {
    if (_timer!.pause()) unawaited(_requestMusic(false));
  }

  void _resume() {
    if (_timer!.resume() && _musicEnabled) unawaited(_requestMusic(true));
  }

  Future<void> _reset() async {
    if (_dialogOpen || _leaving) return;
    final timer = _timer!;
    if (timer.state.isSaving || timer.state.hasUnsavedSession) return;
    final active =
        timer.state.status == TimerStatus.running ||
        timer.state.status == TimerStatus.paused;
    if (active &&
        !await _confirm(
          AppStrings.focusResetTitle,
          AppStrings.focusResetMessage,
          AppStrings.reset,
        )) {
      if (mounted) unawaited(_completeIfReady(timer.state));
      return;
    }
    if (!mounted || _disposing) return;
    if (timer.reset()) await _requestMusic(false);
  }

  Future<void> _back() async {
    if (!_current || _dialogOpen || _leaving) return;
    final timer = _timer!;
    if (timer.state.isSaving) return;
    if (timer.state.hasUnsavedSession) {
      _error(timer.state.errorMessage ?? AppStrings.storageError);
      return;
    }
    final active =
        timer.state.status == TimerStatus.running ||
        timer.state.status == TimerStatus.paused;
    if (active &&
        !await _confirm(
          AppStrings.leaveFocusTitle,
          AppStrings.leaveFocusMessage,
          AppStrings.leave,
        )) {
      if (mounted) unawaited(_completeIfReady(timer.state));
      return;
    }
    if (!mounted || _disposing) return;
    setState(() => _leaving = true);
    try {
      final finish =
          active &&
              (timer.state.status == TimerStatus.running ||
                  timer.state.status == TimerStatus.paused)
          ? timer.finishEarly()
          : Future.value(true);
      final pause = _requestMusic(false);
      final saved = await finish;
      await pause;
      if (!mounted || _disposing) return;
      if (!saved || timer.state.hasUnsavedSession) {
        _error(timer.state.errorMessage ?? AppStrings.storageError);
        return;
      }
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    } catch (error) {
      _error(mapException(error).message);
    } finally {
      if (mounted && !_disposing) setState(() => _leaving = false);
    }
  }

  Future<void> _retrySave() async {
    await _timer!.retrySave();
    if (mounted) unawaited(_completeIfReady(_timer!.state));
  }

  String _status(TimerState state) => state.isSaving
      ? AppStrings.focusSaving
      : switch (state.status) {
          TimerStatus.idle => AppStrings.focusReady,
          TimerStatus.running => AppStrings.focusRunning,
          TimerStatus.paused => AppStrings.focusPaused,
          TimerStatus.finished =>
            state.hasUnsavedSession
                ? AppStrings.focusUnsaved
                : state.lastSession == null
                ? AppStrings.focusEnded
                : AppStrings.focusFinished,
        };

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    key: _messenger,
    child: BlocConsumer<TimerCubit, TimerState>(
      bloc: _timer!,
      listener: (_, state) => _onTimer(state),
      builder: (context, state) {
        final blocked =
            _dialogOpen ||
            _leaving ||
            state.isSaving ||
            state.hasUnsavedSession;
        final active =
            state.status == TimerStatus.running ||
            state.status == TimerStatus.paused;
        final label = switch (state.status) {
          TimerStatus.running => AppStrings.pause,
          TimerStatus.paused => AppStrings.resume,
          _ => AppStrings.start,
        };
        return PopScope(
          canPop: _allowPop,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) unawaited(_back());
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text(AppStrings.focusSession),
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: _leaving || state.isSaving || state.hasUnsavedSession
                    ? null
                    : () => unawaited(_back()),
                icon: const BackButtonIcon(),
              ),
            ),
            body: SafeArea(
              child: Builder(
                builder: (feedback) {
                  _feedbackContext = feedback;
                  if (widget.task == null) {
                    return const EmptyView(
                      icon: Icons.check_circle_outline,
                      title: AppStrings.chooseTask,
                      message: AppStrings.focusReady,
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.task!.title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            FocusCountdown(
                              key: const ValueKey('focus-timer'),
                              state: state,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _status(state),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                for (final minutes
                                    in AppConstants.focusMinutesOptions)
                                  ChoiceChip(
                                    key: ValueKey('focus-duration-$minutes'),
                                    label: Text(AppStrings.minutes(minutes)),
                                    selected: state.selectedMinutes == minutes,
                                    onSelected: blocked || active
                                        ? null
                                        : (_) => _timer!.setDuration(minutes),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: AppButton(
                                    key: ValueKey(
                                      'focus-${label.toLowerCase()}',
                                    ),
                                    label: label,
                                    isLoading: state.isSaving || _leaving,
                                    onPressed: blocked
                                        ? null
                                        : switch (state.status) {
                                            TimerStatus.running => _pause,
                                            TimerStatus.paused => _resume,
                                            _ => _start,
                                          },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AppButton(
                                    key: const ValueKey('focus-reset'),
                                    label: AppStrings.reset,
                                    variant: AppButtonVariant.outlined,
                                    onPressed: blocked
                                        ? null
                                        : () => unawaited(_reset()),
                                  ),
                                ),
                              ],
                            ),
                            if (state.errorMessage != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                state.errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              if (state.hasUnsavedSession)
                                TextButton(
                                  key: const ValueKey('focus-save-retry'),
                                  onPressed: state.isSaving || _leaving
                                      ? null
                                      : () => unawaited(_retrySave()),
                                  child: const Text(AppStrings.retry),
                                ),
                            ],
                            const SizedBox(height: 12),
                            BlocBuilder<AudioCubit, AudioState>(
                              bloc: _audio,
                              builder: (_, audio) => FocusMusicPlayer(
                                state: audio,
                                busy: _musicPending > 0,
                                onPlayPause: () =>
                                    unawaited(_requestMusic(!audio.isPlaying)),
                                onNext: () => unawaited(_nextTrack()),
                                onRetry: () => unawaited(
                                  _requestMusic(
                                    _musicEnabled &&
                                        state.status == TimerStatus.running,
                                    retry: true,
                                  ),
                                ),
                              ),
                            ),
                            SwitchListTile(
                              key: const ValueKey('focus-music-enabled'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                AppStrings.playMusicWithSession,
                              ),
                              value: _musicEnabled,
                              onChanged: _dialogOpen || _leaving
                                  ? null
                                  : (value) {
                                      setState(() => _musicEnabled = value);
                                      if (!value) {
                                        unawaited(_requestMusic(false));
                                      } else if (_timer!.state.status ==
                                          TimerStatus.running) {
                                        unawaited(_requestMusic(true));
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
  );
}
