import 'package:equatable/equatable.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';

class SuggestedPageModel extends Equatable {
  SuggestedPageModel({
    required List<SuggestedTaskModel> todos,
    required this.total,
    required this.skip,
    required this.limit,
  }) : todos = List<SuggestedTaskModel>.unmodifiable(todos) {
    final remaining = total > skip ? total - skip : 0;
    final expected = limit < remaining ? limit : remaining;
    if (total < 0 ||
        skip < 0 ||
        limit < 0 ||
        todos.length != expected ||
        (todos.isEmpty && skip < total) ||
        todos.map((task) => task.id).toSet().length != todos.length) {
      throw const FormatException('Invalid suggested page.');
    }
  }

  final List<SuggestedTaskModel> todos;
  final int total;
  final int skip;
  final int limit;

  bool get hasMore => skip + todos.length < total;

  factory SuggestedPageModel.fromJson(Map<String, dynamic> json) {
    final todos = json['todos'];
    final total = json['total'];
    final skip = json['skip'];
    final limit = json['limit'];
    if (todos is! List || total is! int || skip is! int || limit is! int) {
      throw const FormatException('Invalid suggested page fields.');
    }
    return SuggestedPageModel(
      todos: [
        for (final task in todos)
          if (task is Map<String, dynamic>)
            SuggestedTaskModel.fromJson(task)
          else
            throw const FormatException('Invalid suggested page item.'),
      ],
      total: total,
      skip: skip,
      limit: limit,
    );
  }

  Map<String, dynamic> toJson() => {
    'todos': todos.map((task) => task.toJson()).toList(),
    'total': total,
    'skip': skip,
    'limit': limit,
  };

  @override
  List<Object> get props => [todos, total, skip, limit];
}
