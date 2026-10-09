import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';

typedef PeriodicTickerFactory = Timer Function(
  Duration interval,
  void Function() tick,
);

class TimerCubit extends Cubit<TimerState> {
  TimerCubit(
    this._repository, {
    int initialMinutes = AppConstants.defaultFocusMinutes,
    DateTime Function()? now,
    PeriodicTickerFactory? periodicTicker,
    int Function(int minutes)? secondsForMinutes,
  }) : _now = now ?? DateTime.now,
       _periodicTicker = periodicTicker ?? _defaultTicker,
       _secondsForMinutes = secondsForMinutes ?? _productionSeconds,
       super(_initial(initialMinutes, secondsForMinutes ?? _productionSeconds));

  final FocusRepository _repository;
  final DateTime Function() _now;
  final PeriodicTickerFactory _periodicTicker;
  final int Function(int minutes) _secondsForMinutes;
  Timer? _ticker;
  DateTime? _startedAt;
  DateTime? _segmentStartedAt;
  Duration _elapsed = Duration.zero;
  Duration _segmentHighWater = Duration.zero;
  Future<bool>? _saveFuture;
  Future<void>? _closeFuture;

  static int _productionSeconds(int minutes) => minutes * 60;
  static Timer _defaultTicker(Duration interval, void Function() tick) =>
      Timer.periodic(interval, (_) => tick());

  static TimerState _initial(int minutes, int Function(int) secondsForMinutes) {
    final accepted = AppConstants.focusMinutesOptions.contains(minutes)
        ? minutes
        : AppConstants.defaultFocusMinutes;
    final seconds = _seconds(accepted, secondsForMinutes);
    return TimerState(
      selectedMinutes: accepted,
      totalSeconds: seconds,
      remainingSeconds: seconds,
    );
  }

  static int _seconds(int minutes, int Function(int) converter) {
    final seconds = converter(minutes);
    if (seconds <= 0) throw ArgumentError.value(seconds, 'secondsForMinutes');
    return seconds;
  }

  bool get _blocked => isClosed || state.isSaving || state.hasUnsavedSession;

  bool setDuration(int minutes) {
    if (_blocked ||
        state.status == TimerStatus.running ||
        state.status == TimerStatus.paused) {
      return false;
    }
    if (!AppConstants.focusMinutesOptions.contains(minutes)) {
      emit(state.copyWith(errorMessage: AppStrings.invalidFocusDuration));
      return false;
    }
    final seconds = _seconds(minutes, _secondsForMinutes);
    emit(
      TimerState(
        selectedMinutes: minutes,
        totalSeconds: seconds,
        remainingSeconds: seconds,
        task: state.task,
        revision: state.revision,
      ),
    );
    return true;
  }

  bool start(TaskModel task) {
    if (_blocked ||
        state.status == TimerStatus.running ||
        state.status == TimerStatus.paused) {
      return false;
    }
    _cancelTicker();
    _elapsed = Duration.zero;
    _segmentHighWater = Duration.zero;
    _startedAt = _now();
    _segmentStartedAt = _startedAt;
    emit(
      TimerState(
        status: TimerStatus.running,
        selectedMinutes: state.selectedMinutes,
        totalSeconds: state.totalSeconds,
        remainingSeconds: state.totalSeconds,
        task: task,
        revision: state.revision,
      ),
    );
    _startTicker();
    return true;
  }

  bool pause() {
    if (_blocked || state.status != TimerStatus.running) return false;
    final elapsed = _elapsedAt(_now());
    if (elapsed.inSeconds >= state.totalSeconds) {
      unawaited(_finish(completed: true));
      return true;
    }
    _elapsed = elapsed;
    _segmentStartedAt = null;
    _segmentHighWater = Duration.zero;
    _cancelTicker();
    emit(
      state.copyWith(
        status: TimerStatus.paused,
        remainingSeconds: state.totalSeconds - elapsed.inSeconds,
        clearError: true,
      ),
    );
    return true;
  }

  bool resume() {
    if (_blocked || state.status != TimerStatus.paused) return false;
    _segmentStartedAt = _now();
    _segmentHighWater = Duration.zero;
    emit(state.copyWith(status: TimerStatus.running, clearError: true));
    _startTicker();
    return true;
  }

  bool reset() {
    if (_blocked) return false;
    _cancelTicker();
    _elapsed = Duration.zero;
    _segmentHighWater = Duration.zero;
    _segmentStartedAt = null;
    _startedAt = null;
    emit(
      TimerState(
        selectedMinutes: state.selectedMinutes,
        totalSeconds: state.totalSeconds,
        remainingSeconds: state.totalSeconds,
        task: state.task,
        revision: state.revision,
      ),
    );
    return true;
  }

  void _startTicker() {
    _cancelTicker();
    _ticker = _periodicTicker(const Duration(seconds: 1), _tick);
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Duration _elapsedAt(DateTime now) {
    final start = _segmentStartedAt;
    if (start == null) return _elapsed;
    final segment = now.difference(start);
    if (segment > _segmentHighWater) _segmentHighWater = segment;
    final accumulated = _elapsed + _segmentHighWater;
    final maximum = Duration(seconds: state.totalSeconds);
    return accumulated > maximum ? maximum : accumulated;
  }

  void _tick() {
    if (isClosed || state.status != TimerStatus.running) return;
    final elapsed = _elapsedAt(_now());
    if (elapsed.inSeconds >= state.totalSeconds) {
      unawaited(_finish(completed: true));
    } else {
      emit(
        state.copyWith(
          remainingSeconds: state.totalSeconds - elapsed.inSeconds,
        ),
      );
    }
  }

  Future<bool> finishEarly() {
    if (_blocked ||
        (state.status != TimerStatus.running &&
            state.status != TimerStatus.paused)) {
      return Future.value(false);
    }
    final completed = _elapsedAt(_now()).inSeconds >= state.totalSeconds;
    return _finish(completed: completed);
  }

  Future<bool> _finish({required bool completed}) {
    if (_blocked ||
        (state.status != TimerStatus.running &&
            state.status != TimerStatus.paused)) {
      return Future.value(false);
    }
    final endedAt = _now();
    final elapsed = _elapsedAt(endedAt);
    _elapsed = elapsed;
    _segmentStartedAt = null;
    _segmentHighWater = Duration.zero;
    _cancelTicker();
    final actualSeconds = completed ? state.totalSeconds : elapsed.inSeconds;
    final session = completed || actualSeconds > 10
        ? FocusSessionModel(
            taskId: state.task!.id,
            taskTitle: state.task!.title,
            plannedMinutes: state.selectedMinutes,
            actualSeconds: actualSeconds,
            completed: completed,
            startedAt: _startedAt!,
            endedAt: endedAt.isBefore(_startedAt!) ? _startedAt! : endedAt,
          )
        : null;
    emit(
      state.copyWith(
        status: TimerStatus.finished,
        remainingSeconds: state.totalSeconds - actualSeconds,
        pendingSession: session,
        clearPendingSession: session == null,
        clearError: true,
      ),
    );
    return session == null ? Future.value(true) : _savePending();
  }

  Future<bool> retrySave() {
    if (isClosed || state.isSaving || state.pendingSession == null) {
      return Future.value(false);
    }
    return _savePending();
  }

  Future<bool> _savePending() {
    final session = state.pendingSession;
    if (isClosed || _saveFuture != null || session == null) {
      return Future.value(false);
    }
    emit(state.copyWith(isSaving: true, clearError: true));
    final saving = _persist(session);
    _saveFuture = saving;
    unawaited(
      saving.then((_) {
        if (identical(_saveFuture, saving)) _saveFuture = null;
      }),
    );
    return saving;
  }

  Future<bool> _persist(FocusSessionModel session) async {
    try {
      await _repository.addSession(session);
      if (!isClosed) {
        emit(
          state.copyWith(
            isSaving: false,
            clearPendingSession: true,
            lastSession: session,
            clearError: true,
            revision: state.revision + 1,
          ),
        );
      }
      return true;
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(
            isSaving: false,
            errorMessage: mapException(error).message,
          ),
        );
      }
      return false;
    }
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _cancelTicker();
    final closed = super.close();
    // An already-started save may commit after navigation. Await that attempt,
    // but never emit after disposal or invent a partial session on close.
    return _closeFuture = _closeAfterSave(closed, _saveFuture);
  }

  Future<void> _closeAfterSave(
    Future<void> closed,
    Future<bool>? saving,
  ) async {
    await saving;
    await closed;
  }
}
