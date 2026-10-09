import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, this.task});
  final TaskModel? task;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late TaskPriority _priority;
  DateTime? _dueDate;
  late bool _isDone;
  bool _saving = false;
  bool _discardOpen = false;
  bool _pickingDate = false;
  bool _allowPop = false;
  bool _verifyCreate = false;
  TaskModel? _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    _priority = task?.priority ?? TaskPriority.medium;
    _dueDate = task?.dueDate;
    _isDone = task?.isDone ?? false;
    _titleController.addListener(_edited);
    _descriptionController.addListener(_edited);
  }

  @override
  void dispose() {
    _titleController.removeListener(_edited);
    _descriptionController.removeListener(_edited);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _edited() {
    if (mounted) setState(() => _error = null);
  }

  bool get _dirty {
    final task = widget.task;
    return _titleController.text != (task?.title ?? '') ||
        _descriptionController.text != (task?.description ?? '') ||
        _priority != (task?.priority ?? TaskPriority.medium) ||
        _dueDate != task?.dueDate ||
        _isDone != (task?.isDone ?? false);
  }

  bool get _busy =>
      _saving || context.read<TaskCubit>().state.status == TaskStatus.loading;

  void _leave([TaskModel? result]) {
    if (!mounted || _allowPop) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _back() async {
    if (_busy || _discardOpen || _pickingDate || _allowPop) return;
    if (!_dirty) {
      _leave();
      return;
    }
    _discardOpen = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.discardTitle),
        content: const Text(AppStrings.discardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.discard),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _discardOpen = false;
    if (discard == true && !_busy) _leave();
  }

  Future<void> _chooseDate() async {
    if (_busy || _pickingDate || _discardOpen || _allowPop) return;
    setState(() => _pickingDate = true);
    FocusManager.instance.primaryFocus?.unfocus();
    final initial = (_dueDate ?? DateTime.now()).toLocal();
    var first = DateTime(1900);
    var last = DateTime(2100, 12, 31);
    if (initial.isBefore(first)) first = DateTime(initial.year, 1, 1);
    if (initial.isAfter(last)) last = DateTime(initial.year, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: AppStrings.chooseDate,
      confirmText: AppStrings.done,
      cancelText: AppStrings.cancel,
    );
    if (!mounted) return;
    setState(() {
      _pickingDate = false;
      if (picked != null) {
        _dueDate = picked;
        _error = null;
      }
    });
  }

  TaskModel _candidate() {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final existing = widget.task;
    if (existing != null) {
      return existing.copyWith(
        title: title,
        description: description,
        priority: _priority,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        isDone: _isDone,
      );
    }
    _draft ??= TaskModel(title: title);
    return _draft!.copyWith(
      title: title,
      description: description,
      priority: _priority,
      dueDate: _dueDate,
      clearDueDate: _dueDate == null,
    );
  }

  bool _matches(TaskModel saved, TaskModel candidate) =>
      saved.id == candidate.id &&
      saved.title == candidate.title &&
      saved.description == candidate.description &&
      saved.priority == candidate.priority &&
      saved.dueDate == candidate.dueDate &&
      saved.isDone == candidate.isDone &&
      saved.source == candidate.source;

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    AppSnackbar.showError(context, message);
  }

  Future<void> _save() async {
    if (_busy || _discardOpen || _pickingDate || _allowPop) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cubit = context.read<TaskCubit>();
    if (cubit.isClosed) return;
    final candidate = _candidate();
    setState(() {
      _saving = true;
      _error = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      var update = widget.task != null;
      if (!update && _verifyCreate) {
        // The previous write may have committed before its reread failed.
        // Keep one UUID and reconcile through the Cubit before retrying.
        await cubit.load();
        if (!mounted || cubit.isClosed) return;
        if (cubit.state.status != TaskStatus.success) {
          _fail(cubit.state.errorMessage ?? AppStrings.storageError);
          return;
        }
        update = cubit.state.tasks.any((task) => task.id == candidate.id);
      }
      if (update) {
        await cubit.update(candidate);
      } else {
        await cubit.add(candidate);
      }
      if (!mounted || cubit.isClosed) return;
      final result = cubit.state;
      TaskModel? saved;
      for (final task in result.tasks) {
        if (_matches(task, candidate)) {
          saved = task;
          break;
        }
      }
      if (result.status == TaskStatus.success && saved != null) {
        AppSnackbar.showSuccess(context, AppStrings.taskSaved);
        _leave(saved);
      } else {
        _verifyCreate = widget.task == null;
        _fail(result.errorMessage ?? AppStrings.storageError);
      }
    } catch (error) {
      _verifyCreate = widget.task == null;
      _fail(mapException(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TaskCubit, TaskState>(
      builder: (context, state) {
        final busy = _saving || state.status == TaskStatus.loading;
        final enabled = !busy && !_pickingDate && !_allowPop;
        final edit = widget.task != null;
        return PopScope<TaskModel>(
          canPop: _allowPop || (!busy && !_dirty && !_pickingDate),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) unawaited(_back());
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(edit ? AppStrings.editTask : AppStrings.newTask),
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const BackButtonIcon(),
                onPressed: enabled ? () => unawaited(_back()) : null,
              ),
            ),
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            label: AppStrings.title,
                            hint: AppStrings.titleHint,
                            controller: _titleController,
                            validator: Validators.taskTitle,
                            autofocus: !edit,
                            enabled: enabled,
                          ),
                          const SizedBox(height: 20),
                          AppTextField(
                            label: AppStrings.description,
                            hint: AppStrings.descriptionHint,
                            controller: _descriptionController,
                            validator: Validators.description,
                            maxLines: 4,
                            maxLength: AppConstants.descriptionMaxLength,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            enabled: enabled,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppStrings.priority,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedButton<TaskPriority>(
                              segments: [
                                for (final priority in TaskPriority.values)
                                  ButtonSegment(
                                    value: priority,
                                    label: Text(priority.label),
                                  ),
                              ],
                              selected: {_priority},
                              showSelectedIcon: false,
                              onSelectionChanged: enabled
                                  ? (selected) => setState(() {
                                      _priority = selected.single;
                                      _error = null;
                                    })
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            AppStrings.dueDate,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: enabled
                                    ? () => unawaited(_chooseDate())
                                    : null,
                                icon: const Icon(Icons.event_outlined),
                                label: Text(
                                  _dueDate == null
                                      ? AppStrings.chooseDate
                                      : AppDateUtils.formatDate(_dueDate!),
                                ),
                              ),
                              if (_dueDate != null)
                                IconButton(
                                  tooltip: AppStrings.clearDate,
                                  onPressed: enabled
                                      ? () => setState(() {
                                          _dueDate = null;
                                          _error = null;
                                        })
                                      : null,
                                  icon: const Icon(Icons.close_rounded),
                                )
                              else
                                Text(
                                  AppStrings.noDueDate,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                          if (edit) ...[
                            const SizedBox(height: 16),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(AppStrings.done),
                              value: _isDone,
                              onChanged: enabled
                                  ? (done) => setState(() {
                                      _isDone = done;
                                      _error = null;
                                    })
                                  : null,
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          AppButton(
                            label: AppStrings.save,
                            isLoading: busy,
                            onPressed: enabled
                                ? () => unawaited(_save())
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
