import 'package:equatable/equatable.dart';
import 'package:focusdesk/data/models/task_model.dart';

class SuggestedTaskModel extends Equatable {
  const SuggestedTaskModel({
    required this.id,
    required this.todo,
    required this.completed,
    required this.userId,
  });

  final int id;
  final String todo;
  final bool completed;
  final int userId;

  factory SuggestedTaskModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final todo = json['todo'];
    final completed = json['completed'];
    final userId = json['userId'];
    if (id is! int ||
        id <= 0 ||
        todo is! String ||
        todo.trim().isEmpty ||
        completed is! bool ||
        userId is! int ||
        userId <= 0) {
      throw const FormatException('Invalid suggested task.');
    }
    return SuggestedTaskModel(
      id: id,
      todo: todo,
      completed: completed,
      userId: userId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'todo': todo,
    'completed': completed,
    'userId': userId,
  };

  TaskModel toTask({DateTime? now}) {
    final created = now ?? DateTime.now();
    return TaskModel(
      id: 'suggested-$id',
      title: todo.trim(),
      priority: TaskPriority.medium,
      isDone: completed,
      createdAt: created,
      updatedAt: created,
      source: TaskSource.imported,
    );
  }

  @override
  List<Object> get props => [id, todo, completed, userId];
}
