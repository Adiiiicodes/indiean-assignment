import 'package:equatable/equatable.dart';
import 'package:focusdesk/data/models/task_model.dart';

enum TaskStatus { initial, loading, success, failure }

enum TaskStatusFilter { all, pending, done }

class TaskState extends Equatable {
  TaskState({
    this.status = TaskStatus.initial,
    List<TaskModel> tasks = const [],
    this.query = '',
    this.statusFilter = TaskStatusFilter.all,
    this.priorityFilter,
    this.errorMessage,
    this.lastDeleted,
  }) : tasks = List<TaskModel>.unmodifiable(tasks);

  final TaskStatus status;
  final List<TaskModel> tasks;
  final String query;
  final TaskStatusFilter statusFilter;
  final TaskPriority? priorityFilter;
  final String? errorMessage;
  final TaskModel? lastDeleted;

  List<TaskModel> get visibleTasks {
    final search = query.trim().toLowerCase();
    return List<TaskModel>.unmodifiable(
      tasks.where((task) {
        final matchesStatus = switch (statusFilter) {
          TaskStatusFilter.all => true,
          TaskStatusFilter.pending => !task.isDone,
          TaskStatusFilter.done => task.isDone,
        };
        return matchesStatus &&
            (priorityFilter == null || task.priority == priorityFilter) &&
            (search.isEmpty ||
                task.title.toLowerCase().contains(search) ||
                task.description.toLowerCase().contains(search));
      }),
    );
  }

  TaskState copyWith({
    TaskStatus? status,
    List<TaskModel>? tasks,
    String? query,
    TaskStatusFilter? statusFilter,
    TaskPriority? priorityFilter,
    bool clearPriorityFilter = false,
    String? errorMessage,
    bool clearError = false,
    TaskModel? lastDeleted,
    bool clearLastDeleted = false,
  }) => TaskState(
    status: status ?? this.status,
    tasks: tasks ?? this.tasks,
    query: query ?? this.query,
    statusFilter: statusFilter ?? this.statusFilter,
    priorityFilter: clearPriorityFilter
        ? null
        : priorityFilter ?? this.priorityFilter,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    lastDeleted: clearLastDeleted ? null : lastDeleted ?? this.lastDeleted,
  );

  @override
  List<Object?> get props => [
    status,
    tasks,
    query,
    statusFilter,
    priorityFilter,
    errorMessage,
    lastDeleted,
  ];
}
