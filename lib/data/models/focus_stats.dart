import 'package:equatable/equatable.dart';

class FocusStats extends Equatable {
  const FocusStats({
    this.sessionsToday = 0,
    this.focusMinutesToday = 0,
    this.tasksCompletedToday = 0,
    this.currentStreakDays = 0,
  });

  final int sessionsToday;
  final int focusMinutesToday;
  final int tasksCompletedToday;
  final int currentStreakDays;

  @override
  List<Object> get props => [
    sessionsToday,
    focusMinutesToday,
    tasksCompletedToday,
    currentStreakDays,
  ];
}
