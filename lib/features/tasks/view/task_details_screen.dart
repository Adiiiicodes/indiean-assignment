import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:focusdesk/shared/widgets/priority_chip.dart';

class TaskDetailsScreen extends StatefulWidget {
  const TaskDetailsScreen({super.key, this.taskId});
  final String? taskId;

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  bool _mutating = false;
  bool _deleting = false;
  bool _dialogOpen = false;
  bool _navigating = false;
  bool _leaving = false;
  bool _deleteCommitted = false;
  TaskModel? _deleteSnapshot;
  String? _error;

  TaskModel? _find(TaskState state) {
    for (final task in state.tasks) {
      if (task.id == widget.taskId) return task;
    }
    return null;
  }

  bool get _busy =>
      _mutating ||
      _deleting ||
      _dialogOpen ||
      _navigating ||
      _leaving ||
      context.read<TaskCubit>().state.status == TaskStatus.loading;

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    AppSnackbar.showError(context, message);
  }

  void _popDeleted(TaskModel snapshot) {
    if (!mounted || _leaving) return;
    setState(() {
      _deleteSnapshot = snapshot;
      _leaving = true;
    });
    Navigator.of(context).pop(snapshot);
  }

  Future<void> _navigate(String route) async {
    if (_busy || _deleteCommitted) return;
    final task = _find(context.read<TaskCubit>().state);
    if (task == null) return;
    setState(() {
      _navigating = true;
      _error = null;
    });
    try {
      final result = await Navigator.of(context)
          .pushNamed(route, arguments: task);
      if (mounted && route == Routes.taskForm && result is TaskModel) {
        AppSnackbar.showSuccess(context, AppStrings.taskSaved);
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy || _deleteCommitted) return;
    final cubit = context.read<TaskCubit>();
    final task = _find(cubit.state);
    if (task == null || cubit.isClosed) return;
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      await cubit.toggleDone(task.id);
      if (!mounted || cubit.isClosed) return;
      final updated = _find(cubit.state);
      if (cubit.state.status != TaskStatus.success ||
          updated == null ||
          updated.isDone == task.isDone) {
        _fail(cubit.state.errorMessage ?? AppStrings.storageError);
      }
    } catch (error) {
      _fail(mapException(error).message);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    final cubit = context.read<TaskCubit>();
    if (cubit.isClosed) return;
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      await cubit.load();
      if (!mounted || cubit.isClosed) return;
      if (cubit.state.status != TaskStatus.success) {
        _fail(cubit.state.errorMessage ?? AppStrings.storageError);
      } else if (_deleteCommitted && _find(cubit.state) == null) {
        _popDeleted(_deleteSnapshot!);
      } else {
        _deleteCommitted = false;
        _deleteSnapshot = null;
      }
    } catch (error) {
      _fail(mapException(error).message);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || _deleteCommitted) return;
    final cubit = context.read<TaskCubit>();
    final task = _find(cubit.state);
    if (task == null || cubit.isClosed) return;
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.deleteTaskTitle),
        content: const Text(AppStrings.deleteTaskMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (confirmed != true || _busy || cubit.isClosed) return;
    final latest = _find(cubit.state);
    if (latest == null) return;
    final previousDeleted = cubit.state.lastDeleted;
    setState(() {
      _deleting = true;
      _deleteSnapshot = latest;
      _deleteCommitted = false;
      _error = null;
    });
    try {
      await cubit.delete(latest.id);
      if (!mounted || cubit.isClosed) return;
      final result = cubit.state;
      final deleted = result.lastDeleted;
      if (result.status == TaskStatus.success &&
          deleted?.id == latest.id &&
          _find(result) == null) {
        _popDeleted(deleted!);
      } else {
        _deleteCommitted =
            deleted?.id == latest.id && deleted != previousDeleted;
        if (_deleteCommitted) _deleteSnapshot = deleted;
        _fail(result.errorMessage ?? AppStrings.storageError);
      }
    } catch (error) {
      _fail(mapException(error).message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TaskCubit, TaskState>(
      builder: (context, state) {
        final busy = _busy;
        final task =
            _find(state) ??
            ((_deleting || _leaving || _deleteCommitted)
                ? _deleteSnapshot
                : null);
        final enabled = !busy && !_deleteCommitted && task != null;
        return PopScope<TaskModel>(
          canPop: _leaving || !busy,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(AppStrings.taskDetails),
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const BackButtonIcon(),
                onPressed: busy ? null : () => Navigator.of(context).maybePop(),
              ),
              actions: [
                IconButton(
                  tooltip: AppStrings.edit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: enabled
                      ? () => unawaited(_navigate(Routes.taskForm))
                      : null,
                ),
                IconButton(
                  tooltip: AppStrings.delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: enabled ? () => unawaited(_delete()) : null,
                ),
              ],
            ),
            body: SafeArea(
              child: task == null
                  ? state.status == TaskStatus.loading ||
                            state.status == TaskStatus.initial
                        ? const LoadingView()
                        : ErrorView(
                            message: state.status == TaskStatus.failure
                                ? state.errorMessage ?? AppStrings.storageError
                                : AppStrings.taskNotFound,
                            onRetry: () => unawaited(_retry()),
                          )
                  : _content(context, task, state, busy),
            ),
          ),
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    TaskModel task,
    TaskState state,
    bool busy,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error =
        _error ??
        (state.status == TaskStatus.failure ? state.errorMessage : null);
    final now = DateTime.now();
    final overdue = task.isOverdueAt(now);
    final today = task.isDueTodayAt(now);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.status == TaskStatus.loading || _mutating || _deleting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                ),
              HeroMode(
                enabled: !MediaQuery.disableAnimationsOf(context),
                child: Hero(
                  tag: TaskCard.heroTag(task.id),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      task.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        decoration: task.isDone
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  PriorityChip(priority: task.priority.name),
                  Chip(
                    avatar: Icon(
                      task.isDone
                          ? Icons.check_circle_outline_rounded
                          : Icons.schedule_rounded,
                      size: 16,
                    ),
                    label: Text(
                      task.isDone ? AppStrings.done : AppStrings.pending,
                    ),
                  ),
                  if (task.source == TaskSource.imported)
                    const Chip(label: Text(AppStrings.imported)),
                ],
              ),
              const SizedBox(height: 20),
              Text(AppStrings.dueDate, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              if (task.dueDate == null)
                Text(AppStrings.noDueDate, style: theme.textTheme.bodyMedium)
              else ...[
                Text(
                  task.isDone
                      ? AppDateUtils.formatDate(task.dueDate!)
                      : AppDateUtils.relativeDate(task.dueDate!, now: now),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: overdue
                        ? scheme.error
                        : today
                        ? scheme.primary
                        : scheme.onSurface,
                  ),
                ),
                if (!task.isDone &&
                    AppDateUtils.relativeDate(task.dueDate!, now: now) !=
                        AppDateUtils.formatDate(task.dueDate!))
                  Text(
                    AppDateUtils.formatDate(task.dueDate!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              AppButton(
                label: AppStrings.startFocus,
                icon: Icons.play_arrow_rounded,
                onPressed: busy || _deleteCommitted
                    ? null
                    : () => unawaited(_navigate(Routes.focus)),
              ),
              const SizedBox(height: 12),
              AppButton(
                label: task.isDone
                    ? AppStrings.markUndone
                    : AppStrings.markDone,
                variant: AppButtonVariant.outlined,
                isLoading: _mutating && state.status == TaskStatus.loading,
                onPressed: busy || _deleteCommitted
                    ? null
                    : () => unawaited(_toggle()),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  error,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: busy ? null : () => unawaited(_retry()),
                    child: const Text(AppStrings.retry),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _metadata(
                context,
                AppStrings.created,
                AppDateUtils.formatTimestamp(task.createdAt),
              ),
              const SizedBox(height: 16),
              _metadata(
                context,
                AppStrings.updated,
                AppDateUtils.formatTimestamp(task.updatedAt),
              ),
              if (task.description.trim().isNotEmpty) ...[
                const SizedBox(height: 24),
                _metadata(context, AppStrings.description, task.description),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metadata(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(value, style: textTheme.bodyMedium),
      ],
    );
  }
}
