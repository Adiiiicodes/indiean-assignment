import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

enum _DueChoice { yesterday, today, future, none }

class TaskModelQaScreen extends StatefulWidget {
  const TaskModelQaScreen({super.key});

  @override
  State<TaskModelQaScreen> createState() => _TaskModelQaScreenState();
}

class _TaskModelQaScreenState extends State<TaskModelQaScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Native model task');
  final _scroll = ScrollController();
  TaskPriority _priority = TaskPriority.medium;
  _DueChoice _dueChoice = _DueChoice.today;
  bool _done = false;
  TaskModel? _task;
  String _result = 'Choose values, then create and verify the JSON roundtrip.';

  @override
  void dispose() {
    _title.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime? get _dueDate {
    final now = DateTime.now();
    return switch (_dueChoice) {
      _DueChoice.yesterday => DateTime(now.year, now.month, now.day - 1),
      _DueChoice.today => DateTime(now.year, now.month, now.day),
      _DueChoice.future => DateTime(now.year, now.month, now.day + 2),
      _DueChoice.none => null,
    };
  }

  void _run(String action, TaskModel Function() probe) {
    FocusScope.of(context).unfocus();
    try {
      final task = probe();
      setState(() {
        _task = task;
        _result =
            'PASS: $action\n'
            'ID: ${task.id}\n'
            'Title: ${task.title}\n'
            'Priority: ${task.priority.label} (${task.priority.name})\n'
            'Source: ${task.source.name}\n'
            'Done: ${task.isDone}\n'
            'Due: ${task.dueDate?.toIso8601String() ?? 'none'}\n'
            'Overdue: ${task.isOverdue} / Today: ${task.isDueToday}';
      });
    } catch (error) {
      setState(() => _result = 'FAIL: $error');
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _create() {
    if (_form.currentState?.validate() != true) return;
    _run('Create / JSON roundtrip', () {
      final original = TaskModel(
        title: _title.text,
        description: 'Native model probe',
        priority: _priority,
        dueDate: _dueDate,
        isDone: _done,
      );
      final decoded = jsonDecode(jsonEncode(original.toJson()));
      final restored = TaskModel.fromJson(decoded as Map<String, dynamic>);
      if (restored != original) {
        throw StateError('JSON roundtrip changed the task.');
      }
      return restored;
    });
  }

  void _copy() {
    if (_form.currentState?.validate() != true) return;
    _run('Copy / update', () {
      final original = _task!;
      final copied = original.copyWith(
        title: _title.text,
        priority: _priority,
        dueDate: _dueDate,
        clearDueDate: _dueChoice == _DueChoice.none,
        isDone: _done,
        source: TaskSource.imported,
        updatedAt: DateTime.now(),
      );
      if (copied.id != original.id || copied.createdAt != original.createdAt) {
        throw StateError('Copy changed the task identity or creation date.');
      }
      return copied;
    });
  }

  void _clearDueDate() {
    _run('Clear due date', () {
      final cleared = _task!.copyWith(clearDueDate: true);
      if (cleared.dueDate != null) {
        throw StateError('Copy did not clear the due date.');
      }
      _dueChoice = _DueChoice.none;
      return cleared;
    });
  }

  void _malformed() {
    _run('Malformed JSON defaults', () {
      final now = DateTime.now();
      final decoded = jsonDecode(
        '{"id":99,"title":false,"description":[],"priority":"urgent",'
        '"source":"alien","dueDate":[],"isDone":"true",'
        '"createdAt":[],"updatedAt":[]}',
      );
      final task = TaskModel.fromJson(
        decoded as Map<String, dynamic>,
        now: now,
      );
      if (task.id.isEmpty ||
          task.title != AppStrings.untitledTask ||
          task.description.isNotEmpty ||
          task.priority != TaskPriority.medium ||
          task.source != TaskSource.local ||
          task.dueDate != null ||
          task.isDone ||
          task.createdAt != now ||
          task.updatedAt != now) {
        throw StateError('Malformed JSON did not use safe defaults.');
      }
      return task;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Task model QA')),
    body: SafeArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_result),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Probe title',
                controller: _title,
                validator: Validators.taskTitle,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              const Text('Priority'),
              Wrap(
                spacing: 8,
                children: [
                  for (final priority in TaskPriority.values)
                    ChoiceChip(
                      label: Text(priority.label),
                      selected: _priority == priority,
                      onSelected: (_) => setState(() => _priority = priority),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Due date'),
              Wrap(
                spacing: 8,
                children: [
                  for (final choice in _DueChoice.values)
                    ChoiceChip(
                      label: Text(choice.name),
                      selected: _dueChoice == choice,
                      onSelected: (_) => setState(() => _dueChoice = choice),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Done'),
                value: _done,
                onChanged: (value) => setState(() => _done = value),
              ),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (label, callback) in <(String, VoidCallback?)>[
                      ('Create / roundtrip', _create),
                      ('Copy / update', _task == null ? null : _copy),
                      ('Clear due date', _task == null ? null : _clearDueDate),
                      ('Malformed JSON', _malformed),
                    ])
                      SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: AppButton(label: label, onPressed: callback),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
