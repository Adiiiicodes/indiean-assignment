import 'dart:async';

import 'package:flutter/material.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

typedef _ProbeResult = ({
  TaskModel? selected,
  TaskModel? deleted,
  String message,
});

class TaskRepositoryQaScreen extends StatefulWidget {
  const TaskRepositoryQaScreen({required this.repository, super.key});

  final TaskRepository repository;

  @override
  State<TaskRepositoryQaScreen> createState() => _TaskRepositoryQaScreenState();
}

class _TaskRepositoryQaScreenState extends State<TaskRepositoryQaScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Native repository task');
  final _scroll = ScrollController();
  TaskPriority _priority = TaskPriority.medium;
  TaskModel? _selected;
  TaskModel? _deleted;
  String? _busy;
  String _result = 'Add a task, or read saved tasks after a full app restart.';

  String _details(TaskModel task) =>
      '\nID: ${task.id}\nTitle: ${task.title}'
      '\nPriority: ${task.priority.label} / Done: ${task.isDone}'
      '\nCreated: ${task.createdAt.toIso8601String()}'
      '\nUpdated: ${task.updatedAt.toIso8601String()}';

  @override
  void dispose() {
    _title.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run(
    String label,
    Future<_ProbeResult> Function() operation,
  ) async {
    if (_busy != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = label);
    try {
      final result = await operation();
      final tasks = await widget.repository.getTasks();
      if (!mounted) return;
      setState(() {
        _selected = result.selected;
        _deleted = result.deleted;
        final selected = result.selected;
        if (selected != null) {
          _title.text = selected.title;
          _priority = selected.priority;
        }
        final task = selected ?? result.deleted;
        _result =
            'PASS: ${result.message}\nSaved count: ${tasks.length}\n'
            'Selected: ${selected != null} / Undo: ${_deleted != null}'
            '${task == null ? '' : _details(task)}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _result = 'ERROR: ${mapException(error).message}');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  Future<TaskModel> _readRequired(String id) async {
    final task = await widget.repository.getById(id);
    if (task == null) throw const StorageException();
    return task;
  }

  Future<_ProbeResult> _readAll() async {
    final tasks = await widget.repository.getTasks();
    return (
      selected: tasks.isEmpty ? null : tasks.first,
      deleted: _deleted,
      message: tasks.isEmpty ? 'No saved tasks' : 'Saved task restored',
    );
  }

  Future<_ProbeResult> _add() async {
    final task = TaskModel(
      title: _title.text,
      description: 'Native task repository probe',
      priority: _priority,
    );
    await widget.repository.addTask(task);
    final saved = await _readRequired(task.id);
    if (saved != task) throw const StorageException();
    return (selected: saved, deleted: _deleted, message: 'Task added');
  }

  Future<_ProbeResult> _edit() async {
    final original = _selected!;
    final title = _title.text;
    final priority = _priority;
    await widget.repository.updateTask(
      original.copyWith(title: title, priority: priority),
    );
    final saved = await _readRequired(original.id);
    if (saved.id != original.id ||
        saved.createdAt != original.createdAt ||
        saved.title != title ||
        saved.priority != priority) {
      throw const StorageException();
    }
    return (selected: saved, deleted: _deleted, message: 'Task edited');
  }

  Future<_ProbeResult> _toggle() async {
    final original = _selected!;
    await widget.repository.toggleDone(original.id);
    final saved = await _readRequired(original.id);
    if (saved.isDone == original.isDone) throw const StorageException();
    return (selected: saved, deleted: _deleted, message: 'Completion toggled');
  }

  Future<_ProbeResult> _readById() async {
    final saved = await _readRequired(_selected!.id);
    return (selected: saved, deleted: _deleted, message: 'Task read by ID');
  }

  Future<_ProbeResult> _delete() async {
    final task = _selected!;
    await widget.repository.deleteTask(task.id);
    if (await widget.repository.getById(task.id) != null) {
      throw const StorageException();
    }
    return (selected: null, deleted: task, message: 'Task deleted; Undo ready');
  }

  Future<_ProbeResult> _restore() async {
    final task = _deleted!;
    await widget.repository.restoreTask(task);
    final saved = await _readRequired(task.id);
    if (saved != task) throw const StorageException();
    return (
      selected: saved,
      deleted: null,
      message: 'Undo restored exact task',
    );
  }

  Future<_ProbeResult> _clear() async {
    await widget.repository.clearAll();
    if ((await widget.repository.getTasks()).isNotEmpty) {
      throw const StorageException();
    }
    return (selected: null, deleted: null, message: 'All saved tasks cleared');
  }

  Widget _action(
    String label,
    Future<_ProbeResult> Function() operation, {
    bool enabled = true,
    bool validate = false,
  }) => AppButton(
    label: label,
    isLoading: _busy == label,
    onPressed: _busy != null || !enabled
        ? null
        : () {
            if (validate && _form.currentState?.validate() != true) return;
            unawaited(_run(label, operation));
          },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Task repository QA')),
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
              _action('Read all saved tasks', _readAll),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_result),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Saved task title',
                controller: _title,
                validator: Validators.taskTitle,
                enabled: _busy == null,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final priority in TaskPriority.values)
                    ChoiceChip(
                      label: Text(priority.label),
                      selected: _priority == priority,
                      onSelected: _busy == null
                          ? (_) => setState(() => _priority = priority)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _action('Add model', _add, validate: true),
              const SizedBox(height: 12),
              _action(
                'Edit selected',
                _edit,
                enabled: _selected != null,
                validate: true,
              ),
              const SizedBox(height: 12),
              _action('Toggle done', _toggle, enabled: _selected != null),
              const SizedBox(height: 12),
              _action('Read by ID', _readById, enabled: _selected != null),
              const SizedBox(height: 12),
              _action('Delete selected', _delete, enabled: _selected != null),
              const SizedBox(height: 12),
              _action('Restore / Undo', _restore, enabled: _deleted != null),
              const SizedBox(height: 12),
              _action('Clear all', _clear),
            ],
          ),
        ),
      ),
    ),
  );
}
