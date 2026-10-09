import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class TaskCubitQaScreen extends StatefulWidget {
  const TaskCubitQaScreen({required this.repository, super.key});

  final TaskRepository repository;

  @override
  State<TaskCubitQaScreen> createState() => _TaskCubitQaScreenState();
}

class _TaskCubitQaScreenState extends State<TaskCubitQaScreen> {
  static const _probeIds = {
    'qa-cubit-alpha',
    'qa-cubit-beta',
    'qa-cubit-gamma',
  };
  late final TaskCubit _cubit;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  String? _selectedId;
  String? _busy;
  String _result = 'Load saved tasks or seed the three native probe tasks.';

  @override
  void initState() {
    super.initState();
    _cubit = TaskCubit(widget.repository);
    unawaited(_cubit.load());
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  Future<void> _run(String label, Future<void> Function() operation) async {
    if (_busy != null || _cubit.state.status == TaskStatus.loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = label);
    try {
      await operation();
      if (!mounted) return;
      final state = _cubit.state;
      setState(() {
        if (!state.tasks.any((task) => task.id == _selectedId)) {
          _selectedId = null;
        }
        _result = state.status == TaskStatus.failure
            ? 'ERROR: ${state.errorMessage}'
            : 'PASS: $label';
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

  void _checkSuccess() {
    if (_cubit.state.status == TaskStatus.failure) {
      throw StorageException(
        _cubit.state.errorMessage ?? 'Could not save tasks.',
      );
    }
  }

  Future<void> _seed() async {
    if (_cubit.state.tasks.isNotEmpty) {
      throw const ValidationException('Clear probe tasks before seeding.');
    }
    final probes = [
      TaskModel(
        id: 'qa-cubit-alpha',
        title: 'Alpha plan',
        description: 'Coding notes',
        priority: TaskPriority.low,
      ),
      TaskModel(
        id: 'qa-cubit-beta',
        title: 'Beta review',
        priority: TaskPriority.high,
      ),
      TaskModel(
        id: 'qa-cubit-gamma',
        title: 'Gamma complete',
        priority: TaskPriority.high,
        isDone: true,
      ),
    ];
    for (final task in probes) {
      await _cubit.add(task);
      _checkSuccess();
      if (!mounted) return;
    }
  }

  Future<void> _resetAndReload() async {
    _cubit.reset();
    _query.clear();
    if (mounted) setState(() => _selectedId = null);
    await _cubit.load();
  }

  Future<void> _clearProbe() async {
    final tasks = [..._cubit.state.tasks];
    if (tasks.any((task) => !_probeIds.contains(task.id))) {
      throw const ValidationException(
        'Cleanup refused: saved tasks include non-probe data.',
      );
    }
    for (final task in tasks) {
      await _cubit.delete(task.id);
      _checkSuccess();
      if (!mounted) return;
    }
    await _resetAndReload();
  }

  void _clearFilters() {
    _query.clear();
    _cubit.clearFilters();
    setState(() => _result = 'Filters cleared.');
  }

  TaskModel? _selectedTask(TaskState state) {
    for (final task in state.tasks) {
      if (task.id == _selectedId) return task;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => BlocProvider<TaskCubit>.value(
    value: _cubit,
    child: Scaffold(
      appBar: AppBar(title: const Text('Task cubit QA')),
      body: SafeArea(
        child: BlocBuilder<TaskCubit, TaskState>(
          builder: (context, state) {
            final loading = _busy != null || state.status == TaskStatus.loading;
            final selected = _selectedTask(state);
            final actions = <(String, Future<void> Function(), bool)>[
              ('Load', _cubit.load, true),
              ('Seed 3', _seed, true),
              (
                'Edit',
                () {
                  final task = selected!;
                  return _cubit.update(
                    task.copyWith(title: '${task.title} edited'),
                  );
                },
                selected != null,
              ),
              (
                'Toggle',
                () => _cubit.toggleDone(_selectedId!),
                selected != null,
              ),
              ('Delete', () => _cubit.delete(_selectedId!), selected != null),
              ('Undo', _cubit.undoDelete, state.lastDeleted != null),
              ('Reset / reload', _resetAndReload, true),
              ('Clear probe', _clearProbe, true),
              ('Clear filters', () async => _clearFilters(), true),
            ];

            return SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '$_result\n'
                        '${state.status.name}: ${state.visibleTasks.length} visible / ${state.tasks.length} saved / ${state.statusFilter.name} / ${state.priorityFilter?.label ?? 'Any'}\n'
                        'Selected: ${selected?.title ?? 'none'} / Undo: ${state.lastDeleted?.title ?? 'none'}\n'
                        'Visible: ${state.visibleTasks.map((task) => task.title).join(', ')}'
                        '${state.errorMessage == null ? '' : '\nError: ${state.errorMessage}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButtonTheme(
                    data: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.all(8),
                        textStyle: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, operation, enabled) in actions)
                            SizedBox(
                              width: (constraints.maxWidth - 16) / 3,
                              child: AppButton(
                                label: label,
                                isLoading: _busy == label,
                                onPressed: loading || !enabled
                                    ? null
                                    : () => unawaited(_run(label, operation)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Immediate search query',
                    controller: _query,
                    onChanged: _cubit.setQuery,
                    enabled: !loading,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).unfocus();
                      if (_scroll.hasClients) _scroll.jumpTo(0);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final filter in TaskStatusFilter.values)
                        ChoiceChip(
                          label: Text(filter.name),
                          showCheckmark: false,
                          selected: state.statusFilter == filter,
                          onSelected: loading
                              ? null
                              : (_) => _cubit.setStatusFilter(filter),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final priority in <TaskPriority?>[
                        null,
                        ...TaskPriority.values,
                      ])
                        ChoiceChip(
                          label: Text(priority?.label ?? 'Any'),
                          showCheckmark: false,
                          selected: state.priorityFilter == priority,
                          onSelected: loading
                              ? null
                              : (_) => _cubit.setPriorityFilter(priority),
                        ),
                    ],
                  ),
                  for (final task in state.visibleTasks)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: task.id == _selectedId,
                      leading: Icon(
                        task.id == _selectedId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(task.title),
                      subtitle: Text(
                        '${task.priority.label} / ${task.isDone ? 'Done' : 'Pending'}'
                        '${task.description.isEmpty ? '' : '\n${task.description}'}',
                      ),
                      onTap: loading
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              setState(() => _selectedId = task.id);
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                            },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
