import 'package:equatable/equatable.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:uuid/uuid.dart';

enum TaskPriority {
  low,
  medium,
  high;

  String get label => switch (this) {
    low => AppStrings.priorityLow,
    medium => AppStrings.priorityMedium,
    high => AppStrings.priorityHigh,
  };

  static TaskPriority fromValue(Object? value) {
    if (value is TaskPriority) return value;
    return switch (value is String ? value.trim().toLowerCase() : null) {
      'low' => low,
      'high' => high,
      _ => medium,
    };
  }
}

enum TaskSource {
  local,
  imported;

  static TaskSource fromValue(Object? value) {
    if (value is TaskSource) return value;
    return value is String && value.trim().toLowerCase() == 'imported'
        ? imported
        : local;
  }
}

class TaskModel extends Equatable {
  factory TaskModel({
    String? id,
    required String title,
    String description = '',
    TaskPriority priority = TaskPriority.medium,
    DateTime? dueDate,
    bool isDone = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    TaskSource source = TaskSource.local,
  }) {
    final created = createdAt ?? DateTime.now();
    return TaskModel._(
      id: id == null || id.trim().isEmpty ? _uuid.v4() : id,
      title: title,
      description: description,
      priority: priority,
      dueDate: dueDate,
      isDone: isDone,
      createdAt: created,
      updatedAt: updatedAt ?? created,
      source: source,
    );
  }

  const TaskModel._({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.dueDate,
    required this.isDone,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
  });

  static const _uuid = Uuid();

  final String id;
  final String title;
  final String description;
  final TaskPriority priority;
  final DateTime? dueDate;
  final bool isDone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TaskSource source;

  factory TaskModel.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final fallbackNow = now ?? DateTime.now();
    final created = _date(json['createdAt']) ?? fallbackNow;
    final id = json['id'];
    final title = json['title'];
    final description = json['description'];
    return TaskModel(
      id: id is String ? id : null,
      title: title is String && title.trim().isNotEmpty
          ? title
          : AppStrings.untitledTask,
      description: description is String ? description : '',
      priority: TaskPriority.fromValue(json['priority']),
      dueDate: _date(json['dueDate']),
      isDone: json['isDone'] == true,
      createdAt: created,
      updatedAt: _date(json['updatedAt']) ?? created,
      source: TaskSource.fromValue(json['source']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'priority': priority.name,
    'dueDate': dueDate?.toIso8601String(),
    'isDone': isDone,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'source': source.name,
  };

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    TaskPriority? priority,
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? isDone,
    DateTime? createdAt,
    DateTime? updatedAt,
    TaskSource? source,
  }) => TaskModel._(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
    isDone: isDone ?? this.isDone,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    source: source ?? this.source,
  );

  bool get isOverdue => isOverdueAt(DateTime.now());

  bool get isDueToday => isDueTodayAt(DateTime.now());

  bool isOverdueAt(DateTime now) {
    final due = dueDate?.toLocal();
    if (isDone || due == null) return false;
    final today = now.toLocal();
    return DateTime(
      due.year,
      due.month,
      due.day,
    ).isBefore(DateTime(today.year, today.month, today.day));
  }

  bool isDueTodayAt(DateTime now) {
    final due = dueDate;
    return !isDone && due != null && AppDateUtils.isSameDay(due, now);
  }

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    priority,
    dueDate,
    isDone,
    createdAt,
    updatedAt,
    source,
  ];

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    // DateTime.parse normalizes impossible calendar dates instead of rejecting
    // them. Saved task dates should recover to a default rather than shift days.
    final parts = RegExp(
      r'^([+-]?\d{4,6})-?(\d{2})-?(\d{2})(?:[Tt ](\d{2})(?::?(\d{2}))?(?::?(\d{2}))?)?',
    ).firstMatch(value);
    if (parts == null) return null;
    final year = int.parse(parts[1]!);
    final month = int.parse(parts[2]!);
    final day = int.parse(parts[3]!);
    final calendar = DateTime.utc(year, month, day);
    if (calendar.year != year ||
        calendar.month != month ||
        calendar.day != day) {
      return null;
    }
    for (final (group, maximum) in [(4, 23), (5, 59), (6, 59)]) {
      final component = parts[group];
      if (component != null && int.parse(component) > maximum) return null;
    }
    return parsed;
  }
}
