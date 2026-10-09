import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/data/models/suggested_page_model.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/data/models/task_model.dart';

const _json = {
  'id': 42,
  'todo': 'Review the release',
  'completed': true,
  'userId': 7,
};
final _now = DateTime.utc(2026, 10, 10, 9);

void main() {
  test(
    'suggested task preserves all fields through JSON and value equality',
    () {
      final model = SuggestedTaskModel.fromJson(_json);
      expect(model.id, 42);
      expect(model.todo, 'Review the release');
      expect(model.completed, isTrue);
      expect(model.userId, 7);
      expect(model.toJson(), _json);
      expect(SuggestedTaskModel.fromJson(model.toJson()), model);
      for (final replacement in [
        {'id': 43},
        {'todo': 'Other task'},
        {'completed': false},
        {'userId': 8},
      ]) {
        expect(
          SuggestedTaskModel.fromJson({..._json, ...replacement}),
          isNot(model),
        );
      }
    },
  );

  for (final (field, invalid) in [
    ('id', null),
    ('id', 0),
    ('id', -1),
    ('id', 1.5),
    ('id', '42'),
    ('todo', null),
    ('todo', ''),
    ('todo', '   '),
    ('todo', 42),
    ('completed', null),
    ('completed', 'true'),
    ('completed', 1),
    ('userId', null),
    ('userId', 0),
    ('userId', -1),
    ('userId', '7'),
  ]) {
    test('rejects malformed $field=$invalid instead of inventing API data', () {
      expect(
        () => SuggestedTaskModel.fromJson({..._json, field: invalid}),
        throwsFormatException,
      );
    });
  }

  test('missing required API fields are rejected', () {
    for (final field in _json.keys) {
      final missing = {..._json}..remove(field);
      expect(
        () => SuggestedTaskModel.fromJson(missing),
        throwsFormatException,
        reason: field,
      );
    }
  });

  for (final completed in [false, true]) {
    test('mapper creates a stable imported task with completed=$completed', () {
      final model = SuggestedTaskModel.fromJson({
        ..._json,
        'completed': completed,
      });
      final task = model.toTask(now: _now);
      expect(task.id, 'suggested-42');
      expect(task.title, model.todo);
      expect(task.description, isEmpty);
      expect(task.source, TaskSource.imported);
      expect(task.priority, TaskPriority.medium);
      expect(task.isDone, completed);
      expect(task.dueDate, isNull);
      expect(task.createdAt, _now);
      expect(task.updatedAt, _now);
      expect(model.toTask(now: _now.add(const Duration(days: 1))).id, task.id);
      expect(
        SuggestedTaskModel.fromJson({..._json, 'id': 43}).toTask(now: _now).id,
        isNot(task.id),
      );
    });
  }

  test('default mapper captures one clock value for both timestamps', () {
    final before = DateTime.now();
    final task = SuggestedTaskModel.fromJson(_json).toTask();
    final after = DateTime.now();
    expect(task.createdAt.isBefore(before), isFalse);
    expect(task.createdAt.isAfter(after), isFalse);
    expect(task.updatedAt, task.createdAt);
  });

  test(
    'mapper trims display text without altering the original API record',
    () {
      final model = SuggestedTaskModel.fromJson({
        ..._json,
        'todo': '  Review the release  ',
      });
      expect(model.todo, '  Review the release  ');
      expect(model.toTask(now: _now).title, 'Review the release');
      expect(model.toJson()['todo'], '  Review the release  ');
    },
  );

  test('page roundtrip preserves metadata and exposes an immutable copy', () {
    final todo = SuggestedTaskModel.fromJson(_json);
    final input = [todo];
    final page = SuggestedPageModel(
      todos: input,
      total: 50,
      skip: 20,
      limit: 1,
    );
    input.clear();
    expect(page.todos, [todo]);
    expect(() => page.todos.clear(), throwsUnsupportedError);
    expect(page.total, 50);
    expect(page.skip, 20);
    expect(page.limit, 1);
    expect(page.hasMore, isTrue);
    expect(SuggestedPageModel.fromJson(page.toJson()).toJson(), page.toJson());
    expect(SuggestedPageModel.fromJson(page.toJson()), page);
    expect(
      SuggestedPageModel(todos: [todo], total: 51, skip: 20, limit: 1),
      isNot(page),
    );
  });

  test('last and empty pages do not report more results', () {
    final todo = SuggestedTaskModel.fromJson(_json);
    expect(
      SuggestedPageModel(todos: [todo], total: 21, skip: 20, limit: 20).hasMore,
      isFalse,
    );
    expect(
      SuggestedPageModel(todos: const [], total: 0, skip: 0, limit: 20).hasMore,
      isFalse,
    );
    expect(
      SuggestedPageModel.fromJson({
        'todos': [],
        'total': 20,
        'skip': 25,
        'limit': 20,
      }).hasMore,
      isFalse,
    );
    expect(
      SuggestedPageModel.fromJson({
        'todos': [],
        'total': 20,
        'skip': 25,
        'limit': 0,
      }).hasMore,
      isFalse,
    );
  });

  test('page rejects invalid metadata, inconsistent counts and duplicate identities', () {
    final valid = {
      'todos': [_json],
      'total': 1,
      'skip': 0,
      'limit': 20,
    };
    for (final invalid in [
      {...valid, 'todos': null},
      {...valid, 'todos': 'wrong'},
      {
        ...valid,
        'todos': [42],
      },
      {...valid, 'total': null},
      {...valid, 'total': -1},
      {...valid, 'total': '1'},
      {...valid, 'skip': -1},
      {...valid, 'skip': '0'},
      {...valid, 'limit': -1},
      {...valid, 'limit': 0},
      {...valid, 'limit': '20'},
      {...valid, 'total': 0},
      {...valid, 'skip': 1},
      {...valid, 'total': 30},
      {...valid, 'todos': [], 'total': 1, 'limit': 0},
      {
        ...valid,
        'todos': [
          _json,
          {..._json, 'id': 43},
        ],
        'total': 2,
        'limit': 1,
      },
      {
        ...valid,
        'todos': [_json, _json],
        'total': 2,
      },
    ]) {
      expect(
        () => SuggestedPageModel.fromJson(invalid),
        throwsFormatException,
        reason: invalid.toString(),
      );
    }
    for (final field in valid.keys) {
      final missing = {...valid}..remove(field);
      expect(
        () => SuggestedPageModel.fromJson(missing),
        throwsFormatException,
        reason: field,
      );
    }
  });
}
