import 'package:equatable/equatable.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/task_model.dart';

enum TimerStatus { idle, running, paused, finished }

class TimerState extends Equatable {
  const TimerState({
    this.status = TimerStatus.idle,
    this.selectedMinutes = AppConstants.defaultFocusMinutes,
    this.totalSeconds = AppConstants.defaultFocusMinutes * 60,
    this.remainingSeconds = AppConstants.defaultFocusMinutes * 60,
    this.task,
    this.isSaving = false,
    this.errorMessage,
    this.lastSession,
    this.pendingSession,
    this.revision = 0,
  });

  final TimerStatus status;
  final int selectedMinutes;
  final int totalSeconds;
  final int remainingSeconds;
  final TaskModel? task;
  final bool isSaving;
  final String? errorMessage;
  final FocusSessionModel? lastSession;
  final FocusSessionModel? pendingSession;
  final int revision;

  TaskModel? get selectedTask => task;
  bool get hasUnsavedSession => pendingSession != null;
  int get elapsedSeconds => totalSeconds - remainingSeconds;
  double get progress =>
      totalSeconds == 0 ? 0 : (elapsedSeconds / totalSeconds).clamp(0, 1);

  TimerState copyWith({
    TimerStatus? status,
    int? selectedMinutes,
    int? totalSeconds,
    int? remainingSeconds,
    TaskModel? task,
    bool clearTask = false,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    FocusSessionModel? lastSession,
    bool clearLastSession = false,
    FocusSessionModel? pendingSession,
    bool clearPendingSession = false,
    int? revision,
  }) => TimerState(
    status: status ?? this.status,
    selectedMinutes: selectedMinutes ?? this.selectedMinutes,
    totalSeconds: totalSeconds ?? this.totalSeconds,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    task: clearTask ? null : task ?? this.task,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    lastSession: clearLastSession ? null : lastSession ?? this.lastSession,
    pendingSession: clearPendingSession
        ? null
        : pendingSession ?? this.pendingSession,
    revision: revision ?? this.revision,
  );

  @override
  List<Object?> get props => [
    status,
    selectedMinutes,
    totalSeconds,
    remainingSeconds,
    task,
    isSaving,
    errorMessage,
    lastSession,
    pendingSession,
    revision,
  ];
}
