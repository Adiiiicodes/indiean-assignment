import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:focusdesk/shared/widgets/priority_chip.dart';

class SuggestedView extends StatefulWidget {
  const SuggestedView({super.key, this.active = true});
  final bool active;

  @override
  State<SuggestedView> createState() => _SuggestedViewState();
}

class _SuggestedViewState extends State<SuggestedView>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _localImports = <int>{};
  bool _initialQueued = false;
  bool _loadingInitial = false;
  bool _paging = false;
  bool _refreshing = false;

  @override
  bool get wantKeepAlive => true;

  bool get _visible =>
      mounted && widget.active && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _queueInitialLoad();
  }

  @override
  void didUpdateWidget(covariant SuggestedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _messengerKey.currentState?.clearSnackBars();
      _messengerKey.currentState?.removeCurrentSnackBar();
    } else if (!oldWidget.active) {
      _queueInitialLoad();
    }
  }

  void _queueInitialLoad() {
    if (_initialQueued) return;
    _initialQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialQueued = false;
      if (!_visible) return;
      final cubit = context.read<SuggestedCubit>();
      if (!cubit.isClosed && cubit.state.status == SuggestedStatus.initial) {
        unawaited(_loadInitial());
      }
    });
  }

  Future<void> _loadInitial() async {
    if (!_visible || _loadingInitial || _refreshing || _paging) return;
    final cubit = context.read<SuggestedCubit>();
    if (cubit.isClosed || cubit.state.status == SuggestedStatus.loading) return;
    _loadingInitial = true;
    try {
      await cubit.load();
    } finally {
      _loadingInitial = false;
    }
  }

  Future<void> _refresh() async {
    if (!_visible || _loadingInitial || _refreshing || _paging) return;
    final cubit = context.read<SuggestedCubit>();
    if (cubit.isClosed ||
        cubit.state.isLoadingMore ||
        cubit.state.status == SuggestedStatus.loading) {
      return;
    }
    _refreshing = true;
    try {
      await cubit.refresh();
    } finally {
      _refreshing = false;
    }
  }

  void _onScroll() {
    if (!_visible ||
        !_scrollController.hasClients ||
        _scrollController.position.pixels <= 0) {
      return;
    }
    final state = context.read<SuggestedCubit>().state;
    if (state.status == SuggestedStatus.success &&
        state.errorMessage == null &&
        _scrollController.position.extentAfter <= 240) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (!_visible || _paging || _loadingInitial || _refreshing) return;
    final cubit = context.read<SuggestedCubit>();
    if (cubit.isClosed ||
        !cubit.state.hasMore ||
        cubit.state.isLoadingMore ||
        cubit.state.status == SuggestedStatus.loading) {
      return;
    }
    setState(() => _paging = true);
    try {
      await cubit.loadMore();
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  Future<void> _import(
    SuggestedTaskModel item,
    BuildContext snackbarContext,
  ) async {
    if (!_visible || _localImports.contains(item.id)) return;
    final cubit = context.read<SuggestedCubit>();
    if (cubit.isClosed ||
        cubit.state.importedIds.contains(item.id) ||
        cubit.state.importingIds.contains(item.id)) {
      return;
    }
    setState(() => _localImports.add(item.id));
    try {
      final success = await cubit.importTask(item);
      if (!mounted || !snackbarContext.mounted || !_visible || cubit.isClosed) {
        return;
      }
      if (success && cubit.state.importedIds.contains(item.id)) {
        AppSnackbar.showSuccess(snackbarContext, AppStrings.taskImported);
      } else if (success || cubit.state.status == SuggestedStatus.failure) {
        AppSnackbar.showError(
          snackbarContext,
          cubit.state.errorMessage ?? AppStrings.storageError,
        );
      }
    } catch (error) {
      if (mounted && snackbarContext.mounted && _visible) {
        AppSnackbar.showError(snackbarContext, mapException(error).message);
      }
    } finally {
      if (mounted) setState(() => _localImports.remove(item.id));
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Builder(
        builder: (snackbarContext) =>
            BlocConsumer<SuggestedCubit, SuggestedState>(
              listenWhen: (previous, current) =>
                  current.status == SuggestedStatus.initial &&
                  previous.status != current.status,
              listener: (context, state) => _queueInitialLoad(),
              builder: (context, state) => Scaffold(
                body: SafeArea(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (state.items.isEmpty) {
                          final Widget view;
                          if (state.status == SuggestedStatus.initial ||
                              state.status == SuggestedStatus.loading) {
                            view = const LoadingView();
                          } else if (state.status == SuggestedStatus.failure) {
                            view = ErrorView(
                              message:
                                  state.errorMessage ?? AppStrings.networkError,
                              onRetry: () => unawaited(_loadInitial()),
                            );
                          } else {
                            view = const EmptyView(
                              icon: Icons.lightbulb_outline_rounded,
                              title: AppStrings.noSuggestedTitle,
                              message: AppStrings.noSuggestedMessage,
                            );
                          }
                          return ListView(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: constraints.maxHeight,
                                child: view,
                              ),
                            ],
                          );
                        }
                        final showError =
                            state.status == SuggestedStatus.failure &&
                            state.errorMessage != null;
                        return ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: state.items.length + 1,
                          itemBuilder: (context, index) {
                            if (index < state.items.length) {
                              return _item(
                                state.items[index],
                                state,
                                snackbarContext,
                              );
                            }
                            if (showError) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      state.errorMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                    ),
                                    Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: TextButton(
                                        onPressed: () => unawaited(
                                          state.hasMore
                                              ? _loadMore()
                                              : _refresh(),
                                        ),
                                        child: const Text(AppStrings.retry),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            if (state.isLoadingMore ||
                                _paging ||
                                state.status == SuggestedStatus.loading) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    semanticsLabel: AppStrings.loading,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox(height: 8);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Widget _item(
    SuggestedTaskModel item,
    SuggestedState state,
    BuildContext snackbarContext,
  ) {
    final added = state.importedIds.contains(item.id);
    final importing =
        state.importingIds.contains(item.id) || _localImports.contains(item.id);
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('suggested-${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.todo, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                PriorityChip(priority: TaskPriority.medium.name),
                const Chip(label: Text(AppStrings.imported)),
                Chip(
                  label: Text(
                    item.completed ? AppStrings.done : AppStrings.pending,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppButton(
                key: ValueKey('suggested-add-${item.id}'),
                label: added ? AppStrings.added : AppStrings.add,
                icon: added ? Icons.check_rounded : Icons.add_rounded,
                fullWidth: false,
                isLoading: importing,
                onPressed: added || importing || !widget.active
                    ? null
                    : () => unawaited(_import(item, snackbarContext)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
