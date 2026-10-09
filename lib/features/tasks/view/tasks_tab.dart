import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_colors.dart';
import 'package:focusdesk/core/utils/debouncer.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';

class TasksTab extends StatefulWidget {
  const TasksTab({super.key, this.now});

  final DateTime Function()? now;

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> with WidgetsBindingObserver {
  final _debouncer = Debouncer();
  late final TextEditingController _searchController;
  late String _observedQuery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _observedQuery = context.read<TaskCubit>().state.query;
    _searchController = TextEditingController(text: _observedQuery);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  void _search(String value) {
    setState(() {});
    _debouncer.call(() {
      if (mounted) context.read<TaskCubit>().setQuery(value);
    });
  }

  void _clearSearch() {
    _debouncer.cancel();
    _searchController.clear();
    context.read<TaskCubit>().setQuery('');
    setState(() {});
  }

  void _clearFilters() {
    _debouncer.cancel();
    _searchController.clear();
    context.read<TaskCubit>().clearFilters();
    setState(() {});
  }

  void _addTask() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(Navigator.of(context).pushNamed(Routes.taskForm));
  }

  void _showUndo(
    BuildContext snackbarContext,
    TaskCubit cubit,
    TaskModel snapshot,
    String message,
  ) {
    AppSnackbar.showUndo(snackbarContext, message, () {
      if (!cubit.isClosed && cubit.state.lastDeleted == snapshot) {
        unawaited(cubit.undoDelete());
      }
    });
  }

  Future<bool> _delete(TaskModel task, BuildContext snackbarContext) async {
    final cubit = context.read<TaskCubit>();
    if (cubit.state.status == TaskStatus.loading) return false;
    await cubit.delete(task.id);
    if (!mounted || !snackbarContext.mounted || cubit.isClosed) return false;
    final result = cubit.state;
    final deleted = result.lastDeleted;
    final succeeded =
        result.status == TaskStatus.success &&
        deleted?.id == task.id &&
        !result.tasks.any((item) => item.id == task.id);
    if (succeeded) {
      _showUndo(snackbarContext, cubit, deleted!, AppStrings.taskDeleted);
    }
    return succeeded;
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Builder(
        builder: (snackbarContext) => BlocConsumer<TaskCubit, TaskState>(
          listenWhen: (previous, current) =>
              previous.query != current.query ||
              current.status == TaskStatus.initial ||
              (current.status == TaskStatus.failure &&
                  (previous.status != current.status ||
                      previous.errorMessage != current.errorMessage)),
          listener: (context, state) {
            final queryChanged = _observedQuery != state.query;
            _observedQuery = state.query;
            if ((queryChanged || state.status == TaskStatus.initial) &&
                _searchController.text != state.query) {
              _debouncer.cancel();
              _searchController.value = TextEditingValue(
                text: state.query,
                selection: TextSelection.collapsed(offset: state.query.length),
              );
              setState(() {});
            }
            if (state.status == TaskStatus.failure) {
              final message = state.errorMessage ?? AppStrings.storageError;
              final deleted = state.lastDeleted;
              if (deleted != null) {
                _showUndo(
                  snackbarContext,
                  context.read<TaskCubit>(),
                  deleted,
                  message,
                );
              } else {
                AppSnackbar.showError(context, message);
              }
            }
          },
          builder: (context, state) {
            final cubit = context.read<TaskCubit>();
            final loading = state.status == TaskStatus.loading;
            final tasks = state.visibleTasks;
            return Scaffold(
              body: RefreshIndicator(
                onRefresh: cubit.load,
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _header(context)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: AppTextField(
                          label: AppStrings.searchTasks,
                          controller: _searchController,
                          prefixIcon: Icons.search_rounded,
                          textInputAction: TextInputAction.search,
                          onChanged: _search,
                          onFieldSubmitted: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: AppStrings.clearSearch,
                                  onPressed: _clearSearch,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _filters(state, cubit)),
                    if (loading && state.tasks.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: LinearProgressIndicator(),
                      ),
                    if (state.status == TaskStatus.failure &&
                        state.tasks.isNotEmpty)
                      SliverToBoxAdapter(child: _inlineError(state, cubit)),
                    if (state.tasks.isEmpty &&
                        (loading || state.status == TaskStatus.initial))
                      _stateSliver(const LoadingView())
                    else if (state.status == TaskStatus.failure &&
                        state.tasks.isEmpty)
                      _stateSliver(
                        ErrorView(
                          message:
                              state.errorMessage ?? AppStrings.storageError,
                          onRetry: () => unawaited(cubit.load()),
                        ),
                      )
                    else if (tasks.isEmpty)
                      _stateSliver(
                        state.tasks.isEmpty
                            ? EmptyView(
                                compact: true,
                                icon: Icons.checklist_rounded,
                                title: AppStrings.noTasksTitle,
                                message: AppStrings.noTasksMessage,
                                actionLabel: AppStrings.addTask,
                                onAction: loading ? null : _addTask,
                              )
                            : EmptyView(
                                compact: true,
                                icon: Icons.search_off_rounded,
                                title: AppStrings.noResultsTitle,
                                message: AppStrings.noResultsMessage,
                                actionLabel: AppStrings.clearFilters,
                                onAction: _clearFilters,
                              ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        sliver: SliverList.builder(
                          itemCount: tasks.length,
                          findChildIndexCallback: (key) {
                            if (key is! ValueKey<String>) return null;
                            final index = tasks.indexWhere(
                              (task) => task.id == key.value,
                            );
                            return index < 0 ? null : index;
                          },
                          itemBuilder: (context, index) => _taskTile(
                            tasks[index],
                            cubit,
                            loading,
                            snackbarContext,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              floatingActionButton: View.of(context).viewInsets.bottom > 0
                  ? null
                  : FloatingActionButton(
                      tooltip: AppStrings.addTask,
                      onPressed: loading ? null : _addTask,
                      child: const Icon(Icons.add_rounded),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _stateSliver(Widget child) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final remaining =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent;
        return SliverToBoxAdapter(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: remaining > 0 ? remaining : 0,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        var greeting = AppStrings.welcomeBack;
        if (state is Authenticated) {
          final name = state.user.name.trim().split(RegExp(r'\s+')).first;
          final hour = (widget.now?.call() ?? DateTime.now()).toLocal().hour;
          final period = hour < 12
              ? AppStrings.morning
              : hour < 17
              ? AppStrings.afternoon
              : AppStrings.evening;
          if (name.isNotEmpty) greeting = AppStrings.greeting(period, name);
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.headerGradient(theme.colorScheme),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.tagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filters(TaskState state, TaskCubit cubit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final filter in TaskStatusFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(switch (filter) {
                    TaskStatusFilter.all => AppStrings.all,
                    TaskStatusFilter.pending => AppStrings.pending,
                    TaskStatusFilter.done => AppStrings.done,
                  }),
                  selected: state.statusFilter == filter,
                  onSelected: (_) => cubit.setStatusFilter(filter),
                ),
              ),
            const SizedBox(width: 12),
            FilterChip(
              label: const Text(AppStrings.allPriorities),
              selected: state.priorityFilter == null,
              onSelected: (_) => cubit.setPriorityFilter(null),
            ),
            for (final priority in TaskPriority.values)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilterChip(
                  label: Text(priority.label),
                  selected: state.priorityFilter == priority,
                  onSelected: (selected) =>
                      cubit.setPriorityFilter(selected ? priority : null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inlineError(TaskState state, TaskCubit cubit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            state.errorMessage ?? AppStrings.storageError,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: () => unawaited(cubit.load()),
            child: const Text(AppStrings.retry),
          ),
        ],
      ),
    );
  }

  Widget _taskTile(
    TaskModel task,
    TaskCubit cubit,
    bool loading,
    BuildContext snackbarContext,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(task.id),
      direction: loading ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) => _delete(task, snackbarContext),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: scheme.onErrorContainer,
        ),
      ),
      child: TaskCard(
        task: task,
        onToggle: loading ? null : () => unawaited(cubit.toggleDone(task.id)),
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          unawaited(
            Navigator.of(context)
                .pushNamed(Routes.taskDetails, arguments: task.id),
          );
        },
      ),
    );
  }
}
