import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class FocusSessionModel extends Equatable {
  factory FocusSessionModel({
    String? id,
    required String taskId,
    required String taskTitle,
    required int plannedMinutes,
    required int actualSeconds,
    required bool completed,
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    final sessionId = id ?? const Uuid().v4();
    if (sessionId.trim().isEmpty ||
        taskId.trim().isEmpty ||
        taskTitle.trim().isEmpty ||
        plannedMinutes <= 0 ||
        actualSeconds < 0 ||
        endedAt.isBefore(startedAt)) {
      throw const FormatException('Invalid focus session.');
    }
    return FocusSessionModel._(
      id: sessionId,
      taskId: taskId,
      taskTitle: taskTitle,
      plannedMinutes: plannedMinutes,
      actualSeconds: actualSeconds,
      completed: completed,
      startedAt: startedAt,
      endedAt: endedAt,
    );
  }

  const FocusSessionModel._({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.plannedMinutes,
    required this.actualSeconds,
    required this.completed,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final String taskId;
  final String taskTitle;
  final int plannedMinutes;
  final int actualSeconds;
  final bool completed;
  final DateTime startedAt;
  final DateTime endedAt;

  factory FocusSessionModel.fromJson(Map<String, dynamic> json) =>
      FocusSessionModel(
        id: _string(json, 'id'),
        taskId: _string(json, 'taskId'),
        taskTitle: _string(json, 'taskTitle'),
        plannedMinutes: _integer(json, 'plannedMinutes'),
        actualSeconds: _integer(json, 'actualSeconds'),
        completed: _bool(json, 'completed'),
        startedAt: _date(json, 'startedAt'),
        endedAt: _date(json, 'endedAt'),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'plannedMinutes': plannedMinutes,
    'actualSeconds': actualSeconds,
    'completed': completed,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
  };

  FocusSessionModel copyWith({
    String? id,
    String? taskId,
    String? taskTitle,
    int? plannedMinutes,
    int? actualSeconds,
    bool? completed,
    DateTime? startedAt,
    DateTime? endedAt,
  }) => FocusSessionModel(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    taskTitle: taskTitle ?? this.taskTitle,
    plannedMinutes: plannedMinutes ?? this.plannedMinutes,
    actualSeconds: actualSeconds ?? this.actualSeconds,
    completed: completed ?? this.completed,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
  );

  @override
  List<Object> get props => [
    id,
    taskId,
    taskTitle,
    plannedMinutes,
    actualSeconds,
    completed,
    startedAt,
    endedAt,
  ];

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid focus session $key.');
    }
    return value;
  }

  static int _integer(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) throw FormatException('Invalid focus session $key.');
    return value;
  }

  static bool _bool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) throw FormatException('Invalid focus session $key.');
    return value;
  }

  static DateTime _date(Map<String, dynamic> json, String key) {
    final value = _string(json, key);
    final date = DateTime.tryParse(value);
    // DateTime.parse normalizes out-of-range calendar values. Reject those
    // rather than silently moving a saved session into another statistics day.
    final calendar = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(value);
    if (date == null || calendar == null) {
      throw FormatException('Invalid focus session $key.');
    }
    final year = int.parse(calendar[1]!);
    final month = int.parse(calendar[2]!);
    final day = int.parse(calendar[3]!);
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day ||
        int.parse(calendar[4]!) > 23 ||
        int.parse(calendar[5]!) > 59 ||
        int.parse(calendar[6]!) > 59) {
      throw FormatException('Invalid focus session $key.');
    }
    return date;
  }
}
